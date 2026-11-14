# frozen_string_literal: true

# Unit tests for Aspera::Secret::Store::Keeper — SDK client is faked, no Keeper account needed.

begin
  require 'keeper_secrets_manager'
rescue LoadError => e
  # optional gem keeper_secrets_manager not installed (e.g. in CI)
  RSpec.describe('Aspera::Secret::Store::Keeper') { it('requires gem keeper_secrets_manager') { skip(e.message) } }
  return
end
require_relative '../../../lib/aspera/secret/store/factory'
require_relative '../../../lib/aspera/secret/store/keeper'
require 'securerandom'

RSpec.describe(Aspera::Secret::Store::Keeper) do
  let(:password) { SecureRandom.alphanumeric(12) }
  let(:record) do
    KeeperSecretsManager::Dto::KeeperRecord.new(
      'recordUid' => 'UID1',
      'revision'  => 3,
      'data'      => {
        'title'  => 'my_label',
        'type'   => 'login',
        'fields' => [
          {'type' => 'login', 'value' => ['my_user']},
          {'type' => 'password', 'value' => [password]},
          {'type' => 'url', 'value' => ['https://example.com']}
        ],
        'custom' => [{'type' => 'text', 'label' => 'API Key', 'value' => ['my_key']}],
        'notes'  => 'my notes'
      }
    )
  end
  let(:client) { instance_double(KeeperSecretsManager::Core::SecretsManager, get_secrets: [record], hostname: 'keepersecurity.com') }
  let(:store) { Aspera::Secret::Store::Factory.create({type: 'keeper', config: 'e30=', folder_uid: 'F1'}) }

  before { allow(KeeperSecretsManager).to(receive(:from_config).and_return(client)) }

  def ref(path, field = nil) = Aspera::Secret.parse_reference(Aspera::Secret.reference_text(store: 's', path: path, field: field))

  it 'is created by the factory, with checked parameters' do
    expect(store).to(be_a(described_class))
    expect(store.info).to(eq({hostname: 'keepersecurity.com', folder_uid: 'F1'}))
    expect { Aspera::Secret::Store::Factory.create({type: 'keeper', config: 'e30=', url: 'x'}) }.to(raise_error(Aspera::Secret::Error, 'unsupported keys: url'))
    expect { Aspera::Secret::Store::Factory.create({type: 'keeper'}) }.to(raise_error(Aspera::Secret::Error, /\Aconfig: expecting /))
  end

  it 'gets a secret by title or UID' do
    expected = {label: 'my_label', id: 'UID1', username: 'my_user', password: password, url: 'https://example.com', description: 'my notes'}
    expect(store.get(label: 'my_label')).to(eq(expected))
    expect(store.get(label: 'UID1')).to(eq(expected))
    expect(store.get(label: 'none', exception: false)).to(be_nil)
    expect { store.get(label: 'none') }.to(raise_error(/not found/))
    expect(store.ids).to(eq([{id: 'UID1', label: 'my_label'}]))
  end

  it 'reads references: password by default, standard and custom fields' do
    expect(store.read_reference(ref('my_label'))).to(eq({value: password, version: 3, updated_time: nil}))
    expect(store.read_reference(ref('UID1', 'API Key'))[:value]).to(eq('my_key'))
    expect(store.read_reference(ref('my_label', 'username'))[:value]).to(eq('my_user'))
    expect { store.read_reference(ref('my_label', 'none')) }.to(raise_error(Aspera::Secret::Error, 'no field: none'))
    expect(store.read_fields(ref('my_label'))[:fields]).to(include('login', 'password', 'API Key', 'notes'))
    expect(store.read_fields(ref('my_label'))[:fields]).not_to(include('title'))
  end

  it 'creates a login record in the shared folder, deletes by title' do
    allow(client).to(receive(:create_secret))
    allow(client).to(receive(:delete_secret))
    store.set({label: 'new', username: 'u', password: 'p'})
    expect(client).to(have_received(:create_secret).with(
      {type: 'login', title: 'new', fields: [{type: 'login', value: ['u']}, {type: 'password', value: ['p']}]},
      an_object_having_attributes(folder_uid: 'F1')
    ))
    expect { store.set({label: 'my_label', password: 'p'}) }.to(raise_error(/already exist/))
    store.delete(label: 'my_label')
    expect(client).to(have_received(:delete_secret).with('UID1'))
  end
end
