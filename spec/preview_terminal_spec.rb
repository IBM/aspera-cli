# frozen_string_literal: true

# SPDX-FileCopyrightText: IBM Corp.
# SPDX-License-Identifier: Apache-2.0

require_relative 'spec_helper'
require_relative '../lib/aspera/preview/terminal'
require 'chunky_png'
require 'rmagick'

RSpec.describe(Aspera::Preview::Terminal) do
  # Image of 4 x 4 pixels: top half red, bottom half blue
  let(:png_blob) do
    image = ChunkyPNG::Image.new(4, 4, ChunkyPNG::Color.rgb(255, 0, 0))
    2.upto(3) { |y| 4.times { |x| image[x, y] = ChunkyPNG::Color.rgb(0, 0, 255) } }
    image.to_blob
  end
  # Same kind of image, in JPEG: not decoded by ChunkyPNG, decoded by RMagick
  let(:jpeg_blob) do
    image = Magick::Image.new(4, 4) { |info| info.background_color = 'green' }
    image.format = 'JPEG'
    image.to_blob
  end
  # Terminal size: rows, columns
  let(:winsize) { [10, 8] }

  before do
    allow(Aspera::Environment).to(receive(:terminal?).and_return(true))
    allow(Aspera::Environment).to(receive(:terminal_supports_unicode?).and_return(true))
    allow(IO).to(receive(:console).and_return(instance_double(File, winsize: winsize)))
    # Not an iTerm2 compatible terminal, unless a test sets it
    stub_const('ENV', ENV.to_h.except('TERM_PROGRAM', 'LC_TERMINAL'))
  end

  it 'does not render when output is not a terminal' do
    allow(Aspera::Environment).to(receive(:terminal?).and_return(false))
    expect(described_class.build(png_blob)).to(eq('[Image display requires a terminal]'))
  end

  it 'renders a PNG with half blocks, two pixel rows per text row' do
    text = described_class.build(png_blob, text: true, reserve: 0)
    lines = text.split("\n")
    expect(lines).not_to(be_empty)
    expect(lines.all? { |line| line.include?('▄') }).to(be(true))
  end

  it 'renders a PNG with spaces, one pixel row per text row' do
    text = described_class.build(png_blob, text: true, double: false, reserve: 0)
    expect(text).not_to(include('▄'))
    expect(text.split("\n").length).to(be > 1)
  end

  it 'decodes with RMagick an image that ChunkyPNG does not decode' do
    text = described_class.build(jpeg_blob, text: true, double: false, reserve: 0)
    expect(text.split("\n").length).to(be > 1)
  end

  it 'raises when the image cannot be decoded' do
    expect { described_class.build('not an image', text: true) }.to(raise_error(RuntimeError, 'Cannot decode picture.'))
  end

  context 'with an iTerm2 compatible terminal' do
    before { stub_const('ENV', ENV.to_h.merge('TERM_PROGRAM' => 'iTerm.app')) }

    it 'uses the inline image protocol' do
      expect(described_class.build(png_blob)).to(eq("\e]1337;File=inline=1;preserveAspectRatio=1;size=#{png_blob.length}:#{Base64.strict_encode64(png_blob)}\a"))
    end

    it 'renders as text when asked' do
      expect(described_class.build(png_blob, text: true, reserve: 0)).to(include('▄'))
    end

    it 'falls back to the inline image protocol when the image cannot be decoded as text' do
      expect(described_class.build('not an image', text: true)).to(start_with("\e]1337;File="))
    end
  end

  context 'when the terminal does not know its size' do
    let(:winsize) { [0, 0] }

    it 'uses the default size: 24 rows, 80 columns' do
      text = described_class.build(png_blob, text: true, double: false, reserve: 0)
      lines = text.split("\n")
      # 4 x 4 image fit in 24 rows: limited by height, as the font ratio makes characters higher than wide
      expect(lines.length).to(be > 4)
      expect(lines.length).to(be <= 24)
    end
  end

  context 'without console' do
    before { allow(IO).to(receive(:console).and_return(nil)) }

    it 'uses the default size' do
      expect(described_class.build(png_blob, text: true, reserve: 0)).to(include('▄'))
    end
  end
end
