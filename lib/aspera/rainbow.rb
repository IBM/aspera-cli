# frozen_string_literal: true

# Load Rainbow with terminal detection (tty, TERM=dumb, CLICOLOR_FORCE)
# and its String refinement.
# Each file using colors must still activate it with: using Rainbow
require 'rainbow'
require 'rainbow/refinement'
