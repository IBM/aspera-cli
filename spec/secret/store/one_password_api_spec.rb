# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Unit tests for Aspera::Secret::Store::OnePasswordApi — REST client is faked, no 1Password Connect server needed.

require_relative '../../../lib/aspera/secret/store/factory'
require_relative '../../../lib/aspera/secret/store/one_password_api'
require 'securerandom'

RSpec.describe(Aspera::Secret::Store::OnePasswordApi) do
  let(:password) { SecureRandom.alphanumeric(12) }
  let(:items_path) { 'v1/vaults/V1/items' }
  let(:item) do
    {
      'id'     => 'I1',
      'title'  => 'my_label',
      'urls'   => [{'href' => 'https://example.com', 'primary' => true}],
      'fields' => [
        {'id' => 'username', 'value' => 'my_user'},
        {'id' => 'password', 'value' => password},
        {'id' => 'notesPlain', 'value' => 'my notes'}
      ]
    }
  end
  let(:expected) { {label: 'my_label', id: 'I1', username: 'my_user', password: password, url: 'https://example.com', description: 'my notes'} }
  let(:api) { instance_double(Aspera::Rest::Client, base_url: 'http://localhost:8080') }
  let(:store) { described_class.new(url: 'http://localhost:8080', token: SecureRandom.hex(16), vault_id: 'V1') }

  before do
    allow(Aspera::Rest::Client).to(receive(:new).and_return(api))
    allow(api).to(receive(:read).with(items_path).and_return([{'id' => 'I1', 'title' => 'my_label'}]))
    allow(api).to(receive(:read).with("#{items_path}/I1").and_return(item))
    allow(api).to(receive(:read).with(items_path, {filter: 'title eq "my_label"'}).and_return([{'id' => 'I1'}]))
    allow(api).to(receive(:read).with(items_path, {filter: 'title eq "I1"'}).and_return([]))
    allow(api).to(receive(:read).with(items_path, {filter: 'title eq "none"'}).and_return([]))
    allow(api).to(receive(:read).with(items_path, {filter: 'title eq "dup"'}).and_return([{'id' => 'I1'}, {'id' => 'I2'}]))
  end

  it 'gives info' do
    expect(store.info).to(eq({url: 'http://localhost:8080', vault_id: 'V1'}))
  end

  it 'lists ids and all secrets' do
    expect(store.ids).to(eq([{id: 'I1', label: 'my_label'}]))
    expect(store.all).to(eq([expected]))
  end

  it 'gets a secret by title, by item id, or by id parameter' do
    expect(store.get(label: 'my_label')).to(eq(expected))
    expect(store.get(label: 'I1')).to(eq(expected))
    expect(store.get(label: nil, id: 'I1')).to(eq(expected))
  end

  it 'reports missing and ambiguous labels' do
    expect(store.get(label: 'none', exception: false)).to(be_nil)
    expect { store.get(label: 'none') }.to(raise_error(/Secret 'none' not found/))
    expect { store.get(label: 'dup') }.to(raise_error(/Multiple secrets found with label 'dup'/))
  end

  it 'creates an item with all fields' do
    allow(api).to(receive(:create))
    expect(store.set({label: 'none', username: 'u', password: password, description: 'd', url: 'https://example.com'})).to(be_nil)
    expect(api).to(have_received(:create).with(items_path, {
      'title'    => 'none',
      'category' => 'LOGIN',
      'vault'    => {'id' => 'V1'},
      'fields'   => [
        {'id' => 'username', 'type' => 'STRING', 'value' => 'u'},
        {'id' => 'password', 'type' => 'CONCEALED', 'value' => password},
        {'id' => 'notesPlain', 'type' => 'STRING', 'value' => 'd'}
      ],
      'urls'     => [{'href' => 'https://example.com', 'primary' => true}]
    }))
  end

  it 'creates a minimal item, and refuses an existing label' do
    allow(api).to(receive(:create))
    store.set({label: 'none'})
    expect(api).to(have_received(:create).with(items_path, hash_including('fields' => [])))
    expect { store.set({label: 'my_label'}) }.to(raise_error(/already exist/))
  end

  it 'deletes by label or id' do
    allow(api).to(receive(:delete))
    expect(store.delete(label: 'my_label')).to(be_nil)
    store.delete(label: nil, id: 'I2')
    expect(api).to(have_received(:delete).with("#{items_path}/I1"))
    expect(api).to(have_received(:delete).with("#{items_path}/I2"))
    expect { store.delete(label: 'none') }.to(raise_error(/not found/))
  end
end
