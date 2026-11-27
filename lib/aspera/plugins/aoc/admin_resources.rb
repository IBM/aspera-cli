# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative '../node/commands'

module Aspera
  module Plugins
    module Aoc
      # Admin resources of AoC with generic commands: `aoc admin <resource> <operation>`
      module AdminResources
        # Mount of the Node plugin Gen4 commands (`node access_keys do <id> ...`), instance: set per mount point
        NODE_GEN4_MOUNT = {plugin: Node::Commands, at: %i[access_keys do]}.freeze
        # admin objects that can be manipulated
        OBJECTS = %i[
          app_collaborator
          client
          client_access_key
          client_authorization
          client_registration_token
          configuration_policy
          connect_suppressed_permission
          contact
          distribution_list
          distribution_list_membership
          dropbox
          dropbox_membership
          email_template
          file_deletion_policy
          group
          group_membership
          group_permission
          kms_profile
          network_policy
          node
          operation
          organization
          package
          saml_configuration
          self
          short_link
          trend_micro_profile
          user
          watermark_profile
          workspace
          workspace_membership
        ].freeze

        # Per-resource configuration for admin CRUD resources.
        # Keys: path, create_path, list_fields, id_result, require_ws_id, schema, q, ops, extra_ops, singleton, op_setup, op_mount, op_descriptions
        # create_path: path of `create`, when it is not `path`.
        # schema: false when the resource is not in the OpenAPI description (no help on fields and query).
        # q: false when `list` does not accept `q` (AoC fails with 500): the percent selector reads the whole list.
        # Ops other than `create` and `list` read the identifier `<res>_id` (argument of the op node).
        # op_setup: Hash of op => setup method name, for ops that need context derived from the identifier.
        # op_mount: Hash of op => mount: of that op's node.
        # op_descriptions: Hash of op => description, for ops other than standard ones.
        CONFIG = {
          app_collaborator:              {
            list_fields: %w[id aspera_app_type aspera_app_id collaborator_type collaborator_id name email],
            ops:         %i[create list show delete],
            q:           false
          },
          client:                        {
            extra_ops:       %i[set_pub_key],
            extra_op_args:   {set_pub_key: [{name: :private_key_pem}]},
            op_descriptions: {set_pub_key: 'Set public key of client from a private key'}
          },
          client_access_key:             {path: 'admin/client_access_keys'},
          client_authorization:          {list_fields: %w[id client_id entity_type entity_id], ops: %i[create list show delete], q: false},
          client_registration_token:     {
            path:        'admin/client_registration_tokens',
            create_path: 'admin/client_registration/token',
            list_fields: %w[id value data.client_subject_scopes data.name created_at],
            id_result:   'token',
            q:           false
          },
          configuration_policy:          {list_fields: nil, q: false},
          # No name: the percent selector searches the whole list (e.g. `%member_id:`)
          connect_suppressed_permission: {list_fields: %w[id member_type member_id member_name], ops: %i[create list show delete], q: false},
          # A contact is a user, group, shared inbox or distribution list: no identifier of its own, so no `show`, `modify` or `delete`
          contact:                       {list_fields: %w[source_type source_id name email], ops: %i[create list]},
          distribution_list:             {list_fields: %w[id name owner_type owner_id]},
          # `q` accepts only tokens (`<field>:<value>`): the percent selector searches the whole list
          distribution_list_membership:  {list_fields: %w[id distribution_list_id member_type member_id name], ops: %i[create list show delete], q: false},
          dropbox:                       {
            path:            'dropboxes',
            require_ws_id:   true,
            extra_ops:       %i[join_request update_self_registration_link],
            op_descriptions: {join_request: 'Manage join requests (self registration)', update_self_registration_link: 'Renew the self registration link'}
          },
          email_template:                {list_fields: %w[id email_type source_type source_id subject], ops: %i[list show modify], q: false},
          # Query: `node_id`, or `host` and `bucket_name`
          file_deletion_policy:          {singleton: true, op_descriptions: {show: 'Show the nodes of a storage, for a file deletion policy'}},
          dropbox_membership:            {},
          group:                         {extra_ops: %i[shared_folders], op_descriptions: {shared_folders: 'List the shared folders that the group can access'}},
          # A membership cannot be modified (no `PUT` in the API): delete it and create another one
          group_membership:              {list_fields: %w[id group_id member_type member_id], ops: %i[create list show delete]},
          group_permission:              {list_fields: %w[id group_id level entity_type entity_id]},
          kms_profile:                   {path: 'integrations/kms_profiles', q: false, extra_ops: %i[nodes], op_descriptions: {nodes: 'List the nodes that use the profile'}},
          # Rules: initiation (nodes to initiate with) and access control (nodes allowed or not)
          network_policy:                {
            list_fields:     nil,
            extra_ops:       %i[initiation_rule access_control_rule],
            op_descriptions: {initiation_rule: 'Manage the nodes to initiate transfers with', access_control_rule: 'Manage the nodes allowed or disallowed'}
          },
          node:                          {
            list_fields:     %w[id name host access_key],
            extra_ops:       %i[do bearer_token update_status],
            extra_op_args:   {bearer_token: [{name: :scope, mandatory: false, default: nil}]},
            op_mount:        {do: NODE_GEN4_MOUNT.merge(instance: :admin_node_do_plugin)},
            op_descriptions: {do: 'Execute command on node', bearer_token: 'Generate bearer token for node', update_status: 'Ask AoC to scan node and update its status'}
          },
          operation:                     {list_fields: %w[id type status created_at updated_at workspace_id user_id workspace_membership_id group_membership_id], ops: %i[list show modify]},
          organization:                  {singleton: true, ops: %i[show modify]},
          package:                       {extra_ops: %i[download_counts], op_descriptions: {download_counts: 'List the downloads of the package by user'}},
          saml_configuration:            {q: false},
          self:                          {singleton: true, op_descriptions: {show: 'Show current user'}},
          # No `show`: AoC has no `GET /short_links/{id}`, and the list cannot be filtered by identifier
          short_link:                    {
            list_fields: %w[id short_url data.url_token_data.purpose password_enabled password_protected updated_by_user_id updated_at],
            ops:         %i[create list modify delete],
            q:           false
          },
          trend_micro_profile:           {path: 'integrations/trend_micro_profiles', list_fields: %w[id name provider region bucket_name]},
          user:                          {
            list_fields:     %w[id name email],
            extra_ops:       %i[preferences notifications invite shared_folders],
            op_descriptions: {
              preferences:    'Manage user preferences',
              notifications:  'Manage user notification preferences',
              invite:         'Send again the invitation of the user to the organization (email)',
              shared_folders: 'List the shared folders that the user can access'
            }
          },
          watermark_profile:             {path: 'integrations/watermark_profiles', list_fields: %w[id name cloud_provider cloud_region]},
          workspace:                     {
            extra_ops:       %i[shared_folder dropbox],
            op_setup:        {shared_folder: :setup_admin_workspace_shared_folder, dropbox: :setup_admin_workspace_dropbox},
            op_descriptions: {shared_folder: 'Manage shared folders of workspace', dropbox: 'Manage shared inboxes of workspace'}
          },
          workspace_membership:          {list_fields: %w[id workspace_id member_type member_id]}
        }.freeze
      end
    end
  end
end
