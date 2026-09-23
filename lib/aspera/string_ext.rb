# frozen_string_literal: true

class ::String
  # Transform capitalized to snake case
  def capital_to_snake
    return gsub(/([a-z\d])([A-Z])/, '\1_\2')
        .gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
        .downcase
  end

  # Transform snake case to capitalized
  def snake_to_capital
    split('_').map(&:capitalize).join
  end
end
