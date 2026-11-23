# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

# Shim: moved to aspera/plugins/faspex5/faspex4_post_proc_servlet, removed in 5.0
require_relative 'log'
require_relative 'plugins/faspex5/faspex4_post_proc_servlet'
Aspera::Log.log.warn('aspera/faspex_postproc is deprecated: use aspera/plugins/faspex5/faspex4_post_proc_servlet (removed in 5.0)')
module Aspera
  Faspex4PostProcServlet = Aspera::Plugins::Faspex5::Faspex4PostProcServlet
  deprecate_constant :Faspex4PostProcServlet
end
