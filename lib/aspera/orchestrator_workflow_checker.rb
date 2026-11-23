# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/orchestrator/workflow_checker, removed in 5.0
require_relative 'log'
require_relative 'plugins/orchestrator/workflow_checker'
Aspera::Log.log.warn('aspera/orchestrator_workflow_checker is deprecated: use aspera/plugins/orchestrator/workflow_checker (removed in 5.0)')
module Aspera
  OrchestratorWorkflowChecker = Aspera::Plugins::Orchestrator::WorkflowChecker
  deprecate_constant :OrchestratorWorkflowChecker
end
