require 'asperalm/rest'

module Asperalm
  module Cli
    module Plugins
      class Bss < BasicAuthPlugin

        ACTIONS=[ :subscription ]

        FIELDS={
          'bssSubscriptions' => %w{id name termVolumeGb termMonths trial startDate endDate plan renewalType chargeAgreementNumber customerName}
        }

        def initialize(env)
          super(env)
          if env.has_key?(:bss_api)
            @api_bss=env[:bss_api]
          end
        end

        def all_fields(name)
          return FIELDS[name].join(' ')
        end

        def execute_action
          if @api_bss.nil?
            key = self.options.get_option(:password,:mandatory)
            @api_bss=Rest.new(
            base_url: 'https://dashboard.bss.asperasoft.com/platform',
            headers: {cookie: "_dashboard_key=#{key}"})
          end
          command=self.options.get_next_command(ACTIONS)
          case command
          when :subscription
            command=self.options.get_next_command([:find,:show, :instances])
            object='bssSubscriptions'
            case command
            when :find
              query = self.options.get_option(:query,:mandatory) # AOC_ORGANIZATION_QUERY AOC_USER_EMAIL
              value = self.options.get_option(:value,:mandatory)
              request={
                'variables'=>{'filter'=>{'key'=>query,'value'=>value}},
                'query'=>"query($filter: BssSubscriptionFilter!) {#{object}(filter: $filter) { #{all_fields('bssSubscriptions')} } }"
              }
              result=@api_bss.create('graphql',request)[:data]
              # give fields to keep order
              return {:type=>:object_list, :data=>result['data'][object],:fields=> FIELDS['bssSubscriptions']}
            when :show
              id = self.options.get_option(:id,:mandatory)
              request={
                'variables'=>{'id'=>id},
                'query'=>"query($id: ID!) {#{object}(id: $id) { #{all_fields('bssSubscriptions')} roleAssignments(uniqueSubjectId: true) { id subjectId } instances { id state planId serviceId ssmSubscriptionId entitlement { id } aocOrganization { id subdomainName name status tier urlId trialExpiresAt users(organizationAdmin: true) { id name email atsAdmin subscriptionAdmin } } } } }"
              }
              result=@api_bss.create('graphql',request)[:data]['data'][object].first
              result.delete('instances')
              return {:type=>:single_object, :data=>result}
            when :instances
              id = self.options.get_option(:id,:mandatory)
              request={
                'variables'=>{'id'=>id},
                'query'=>"query($id: ID!) {#{object}(id: $id) { aocOrganization { id subdomainName name status tier urlId trialExpiresAt } } } }"
              }
              result=@api_bss.create('graphql',request)[:data]['data'][object].first
              return {:type=>:object_list, :data=>result['instances']}
            end
          end
        end
      end # Bss
    end # Plugins
  end # Cli
end # Asperalm
