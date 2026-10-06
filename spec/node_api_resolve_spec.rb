# frozen_string_literal: true

require 'bundler/setup'
require 'aspera/api/node'

RSpec.describe(Aspera::Api::Node) do
  describe '#resolve_api_fid' do
    # Folder contents by file id (listing order matters: siblings listed after the matching folder)
    let(:tree) do
      {
        'root'        => [
          {'name' => 'a', 'type' => 'folder', 'id' => 'a'},
          {'name' => 'lnk', 'type' => 'link', 'id' => 'lnk', 'target_node_id' => 'n2', 'target_id' => 'lnk_target'},
          {'name' => 'lnk_empty', 'type' => 'link', 'id' => 'lnk_empty', 'target_node_id' => 'n2', 'target_id' => 'empty'},
          {'name' => 'sub', 'type' => 'folder', 'id' => 'sibling_sub'}
        ],
        'a'           => [
          {'name' => 'b', 'type' => 'folder', 'id' => 'a_b'},
          {'name' => 'c', 'type' => 'folder', 'id' => 'a_c'},
          {'name' => 'd', 'type' => 'folder', 'id' => 'a_d'}
        ],
        'a_b'         => [
          {'name' => 'c', 'type' => 'folder', 'id' => 'a_b_c'},
          {'name' => 'f.txt', 'type' => 'file', 'id' => 'a_b_f'}
        ],
        'lnk_target'  => [{'name' => 'sub', 'type' => 'folder', 'id' => 'link_sub'}],
        'empty'       => [],
        'a_c'         => [],
        'a_d'         => [],
        'a_b_c'       => [],
        'sibling_sub' => [],
        'link_sub'    => []
      }
    end
    # Ids of listed folders
    let(:listed) { [] }

    # Node API without server, folder contents from `tree`, links on same node
    let(:api) do
      api = Aspera::Api::Node.allocate
      allow(api).to(receive(:read_folder_content)) do |file_id, *_args, **_kwargs|
        listed.push(file_id)
        tree.fetch(file_id)
      end
      allow(api).to(receive(:node_id_to_node).and_return(api))
      api
    end

    def resolve(path)
      api.resolve_api_fid('root', path).file_id
    end

    it 'resolves a folder' do
      expect(resolve('/a/b')).to(eq('a_b'))
    end

    it 'resolves a file' do
      expect(resolve('/a/b/f.txt')).to(eq('a_b_f'))
    end

    it 'resolves the top folder' do
      expect(resolve('/')).to(eq('root'))
    end

    it 'resolves the child, not a sibling with the same name' do
      expect(resolve('/a/b/c')).to(eq('a_b_c'))
      expect(listed).to(eq(%w[root a a_b]))
    end

    it 'does not resolve to a sibling when the child does not exist' do
      expect { resolve('/a/b/d') }.to(raise_error(Aspera::ParameterError, 'Entry not found: d in /a/b'))
    end

    it 'resolves through a link' do
      expect(resolve('/lnk/sub')).to(eq('link_sub'))
    end

    it 'does not resolve to a sibling of a link when not found in link target' do
      expect { resolve('/lnk_empty/sub') }.to(raise_error(Aspera::ParameterError, 'Entry not found: sub in /lnk_empty'))
    end
  end
end
