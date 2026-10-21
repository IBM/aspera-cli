# frozen_string_literal: true

require 'spec_helper'
require 'net/http'
require 'aspera/rest/aspera_errors'

RSpec.describe(Aspera::Rest::ErrorAnalyzer) do
  it 'has Aspera handlers registered once on require' do
    req = Net::HTTP::Get.new('/api')
    req['host'] = 'example.com'
    http = instance_double(Net::HTTPResponse, code: '400', message: 'Bad Request')
    expect { described_class.instance.raise_on_error(req, {'message' => 'boom'}, http) }
      .to(raise_error(Aspera::Rest::CallError, "boom\nexample.com 400 Bad Request"))
  end

  it 'removes the backtrace of a Ruby exception returned by Orchestrator' do
    req = Net::HTTP::Get.new('/aspera/orchestrator/api/export_workflow/130')
    req['host'] = 'example.com'
    http = instance_double(Net::HTTPResponse, code: '404', message: 'Not Found')
    message = [
      "/opt/aspera/orchestrator/lib/import_exporter.rb:171:in `write': Minitar::Writer::WriteBoundaryOverflow (Minitar::Writer::WriteBoundaryOverflow)",
      "\tfrom /opt/aspera/orchestrator/lib/import_exporter.rb:171:in `block in export'",
      "\tfrom /opt/aspera/orchestrator/app/models/workflow.rb:12:in 'Workflow#export'"
    ].join("\n")
    body = %Q(<?xml version="1.0"?><error time="2026-10-21 07:54:01 UTC" action="export_workflow" id="130">\n#{message}\n</error>)
    expect { described_class.instance.raise_on_error(req, body, http) }
      .to(raise_error(Aspera::Rest::CallError) { |error| expect(error.message).not_to(include('from /opt')) })
    expect { described_class.instance.raise_on_error(req, body, http) }
      .to(raise_error(Aspera::Rest::CallError, /import_exporter.rb:171:in `write': Minitar::Writer::WriteBoundaryOverflow/))
  end
end
