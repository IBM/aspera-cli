# frozen_string_literal: true

# Unit tests for Aspera::Cli::Plugins::Preview event processing on remote storage (`--root-url=aspera:`).
# Node API, transfer agent and preview generator are doubled: no node server, no ImageMagick/ffmpeg needed.

require_relative '../lib/aspera/cli/context'
require_relative '../lib/aspera/cli/parser'
require_relative '../lib/aspera/cli/plugins/preview'
require_relative '../lib/aspera/cli/transfer_agent'
require_relative '../lib/aspera/cli/runner'
require_relative '../lib/aspera/persistency_folder'
require 'securerandom'
require 'tmpdir'

module Aspera
  module Cli
    module Plugins
      RSpec.describe(Preview) do
        let(:node) { instance_double(Api::Node, base_url: 'https://node.example.com') }
        let(:transfer) { instance_double(TransferAgent, user_transfer_spec: {}) }
        let(:generator) { instance_double(Aspera::Preview::Generator, conversion_type: :image, error_asset: error_asset) }
        let(:tmp) { Dir.mktmpdir }
        let(:error_asset) { File.join(tmp, 'error.png').tap { |f| File.write(f, 'png') } }
        # Directions of started transfers
        let(:transfers) { [] }
        # Logged errors and warnings
        let(:logged) { [] }
        # File in a folder, as listed by node API
        let(:file_entry) { {'id' => 'f2', 'name' => 'a.png', 'type' => 'file', 'content_type' => 'image/png'} }

        before do
          allow(Api::Node).to(receive(:new).and_return(node))
          allow(Aspera::Preview::Utils).to(receive(:check_tools))
          allow(Aspera::Preview::Generator).to(receive(:new).and_return(generator))
          allow(generator).to(receive(:generate).and_raise('conversion failed'))
          allow(TempFileManager.instance).to(receive(:global_temp).and_return(tmp))
          %i[error warn].each do |level|
            allow(Log.log).to(receive(level)) { |*args, &block| logged.push(block ? block.call : args.first) }
          end
          allow(node).to(receive(:read)) do |path, *_args, **_kwargs|
            case path
            when 'access_keys/self' then {'id' => 'ak1', 'root_file_id' => '1', 'storage' => {'type' => 's3'}}
            when 'info' then {}
            when 'files/d1' then {'id' => 'd1', 'path' => '/d', 'type' => 'folder'}
            when 'files/f2' then {'id' => 'f2'}
            when 'files/f2/preview' then raise Rest::CallError, 'no preview'
            when 'events' then events.shift || []
            else raise Rest::CallError, "unexpected #{path}"
            end
          end
          allow(node).to(receive(:read_folder_content)) do |id, *_args|
            case id
            when '1' then [{'id' => 'p1', 'name' => 'previews'}]
            when 'd1' then [file_entry, {'id' => 'l1', 'name' => 'lnk', 'type' => 'link'}, {'id' => 'u1', 'name' => 'u', 'type' => 'weird'}]
            end
          end
          allow(node).to(receive(:transfer_spec_gen4)) { |_id, direction, _ts| {'direction' => direction} }
          allow(transfer).to(receive(:start)) do |tspec|
            transfers.push(tspec['direction'])
            # Simulate the download of the original file
            File.write(File.join(transfer.user_transfer_spec['destination_root'], 'a.png'), 'png') if tspec['direction'].eql?('receive')
            Transfer::Result::Success.new
          end
        end

        after { FileUtils.rm_rf(tmp) }

        # @param argv [Array<String>] command line
        def execute(*argv)
          context = Context.new
          context.man_header = false
          context.options = Parser.new('test', argv + ['--url=https://node.example.com', '--username=ak1', "--password=#{SecureRandom.alphanumeric(12)}"])
          context.options.declare(:once_only, description: 'Process only new items', allowed: Type::BOOLEAN, default: false)
          context.transfer = transfer
          context.persistency = PersistencyFolder.new(File.join(tmp, 'persistency'))
          described_class.new(context: context).execute_action
        end

        describe 'existing remote preview' do
          let(:events) { [[{'id' => 1, 'data' => {'direction' => 'receive', 'status' => 'completed', 'error_code' => 0, 'file_id' => 'd1'}}]] }

          before { allow(node).to(receive(:read).with('files/f2/preview', anything).and_return('png')) }

          %w[never mtime].each do |overwrite|
            it "is not generated again with overwrite #{overwrite}" do
              execute('trevents', "--overwrite=#{overwrite}")
              expect(transfers).to(be_empty)
            end
          end
        end

        describe 'scan of local storage' do
          let(:events) { [] }
          let(:storage) { File.join(tmp, 'storage').tap { |dir| FileUtils.mkdir_p(File.join(dir, 'previews')) } }

          it 'writes the access key marker, and ignores errors in folders' do
            allow(node).to(receive(:read_folder_content).with('d1').and_raise(Rest::CallError, 'folder gone'))
            expect(execute('scan', '%id:d1', "--root-url=#{UriReader.file_url(storage)}").data).to(eq('scan finished'))
            expect(File.read(File.join(storage, 'previews', '.aspera_access_key'))).to(eq('ak1'))
            expect(logged).to(include('An error occurred: folder gone, ignoring'))
          end
        end

        describe 'trevents' do
          # Download completed in folder `d1`
          let(:download) { {'id' => 1, 'data' => {'direction' => 'receive', 'status' => 'completed', 'error_code' => 0, 'file_id' => 'd1'}} }
          let(:events) { [[download]] }

          it 'downloads, generates (error asset on failure) and uploads previews of files of the folder' do
            expect(execute('trevents').data).to(eq('trevents finished'))
            expect(transfers).to(eq(%w[receive send]))
            expect(logged).to(include('Ignoring: RuntimeError conversion failed', 'unknown entry type: weird'))
          end

          it 'retries without iteration token if refused' do
            calls = 0
            allow(node).to(receive(:read).with('events', anything)) do
              calls += 1
              raise Rest::CallError, 'Invalid iteration_token' if calls.eql?(1)
              []
            end
            execute('trevents')
            expect(calls).to(eq(2))
            expect(logged).to(include(/Retrying without iteration token/))
          end

          it 'raises other errors' do
            allow(node).to(receive(:read).with('events', anything).and_raise(Rest::CallError, 'forbidden'))
            expect { execute('trevents') }.to(raise_error(Rest::CallError, 'forbidden'))
          end

          it 'skips a format' do
            execute('trevents', '--skip-format=mp4')
            expect(transfers).to(eq(%w[receive send]))
          end

          it 'skips types' do
            execute('trevents', '--skip-types=image')
            expect(transfers).to(be_empty)
          end
        end

        describe 'events' do
          # @param types [Array<String>] types of the file event
          def file_event(*types) = {'id' => 1, 'types' => types, 'data' => {'type' => 'file', 'id' => 'f2', 'parent_file_id' => 'd1'}}

          let(:events) { [[file_event('file.created')]] }

          before { allow(node).to(receive(:read).with('files/f2').and_return(file_entry.merge('path' => '/d/a.png'))) }

          it 'generates previews of new files' do
            expect(execute('events').data).to(eq('events finished'))
            expect(transfers).to(eq(%w[receive send]))
          end

          it 'applies the filter' do
            execute('events', '--filter=*.mxf')
            expect(transfers).to(be_empty)
          end

          context 'with a deleted file' do
            before { events.replace([[file_event('file.deleted')]]) }

            it 'deletes its preview folder on remote storage' do
              allow(node).to(receive(:read_folder_content).with('p1', {name: 'f2.asp-preview'}).and_return([{'id' => 'pv2', 'name' => 'f2.asp-preview'}]))
              allow(node).to(receive(:delete))
              execute('events')
              expect(node).to(have_received(:delete).with('files/pv2'))
              expect(node).not_to(have_received(:read).with('files/f2'))
            end

            it 'does nothing on remote storage if there is no preview' do
              allow(node).to(receive(:read_folder_content).with('p1', anything).and_return([]))
              allow(node).to(receive(:delete))
              execute('events')
              expect(node).not_to(have_received(:delete))
            end

            it 'deletes its preview folder on local storage' do
              storage = File.join(tmp, 'storage')
              preview_dir = File.join(storage, 'previews', 'f2.asp-preview')
              FileUtils.mkdir_p(preview_dir)
              File.write(File.join(preview_dir, 'preview.png'), 'png')
              execute('events', "--root-url=#{UriReader.file_url(storage)}")
              expect(File.exist?(preview_dir)).to(be(false))
            end

            it 'logs an error if the preview cannot be deleted' do
              allow(node).to(receive(:read_folder_content).with('p1', anything).and_return([{'id' => 'pv2', 'name' => 'f2.asp-preview'}]))
              allow(node).to(receive(:delete).and_raise(Rest::CallError, 'forbidden'))
              expect(execute('events').data).to(eq('events finished'))
              expect(logged).to(include('Cannot delete preview of f2: forbidden'))
            end
          end

          it 'resumes from the last processed event with once only' do
            filters = []
            allow(node).to(receive(:read).with('events', anything)) do |_path, filter|
              filters.push(filter.dup)
              filters.length.eql?(1) ? [{'id' => 7, 'data' => {'type' => 'folder'}}] : []
            end
            2.times { execute('events', '--once-only=yes') }
            expect(filters.map { |filter| filter['iteration_token'] }).to(eq([nil, '7']))
          end
        end

        it 'requires the previews folder on remote storage' do
          allow(node).to(receive(:read_folder_content).and_return([]))
          expect { execute('scan') }.to(raise_error(Cli::Error, /Folder \.?previews does not exist on node/))
        end
      end
    end
  end
end
