# -*- encoding: utf-8; frozen_string_literal: true -*-
#
#--
# This file is part of HexaPDF.
#
# HexaPDF - A Versatile PDF Creation and Manipulation Library For Ruby
# Copyright (C) 2014-2017 Thomas Leitner
#
# HexaPDF is free software: you can redistribute it and/or modify it
# under the terms of the GNU Affero General Public License version 3 as
# published by the Free Software Foundation with the addition of the
# following permission added to Section 15 as permitted in Section 7(a):
# FOR ANY PART OF THE COVERED WORK IN WHICH THE COPYRIGHT IS OWNED BY
# THOMAS LEITNER, THOMAS LEITNER DISCLAIMS THE WARRANTY OF NON
# INFRINGEMENT OF THIRD PARTY RIGHTS.
#
# HexaPDF is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public
# License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with HexaPDF. If not, see <http://www.gnu.org/licenses/>.
#
# The interactive user interfaces in modified source and object code
# versions of HexaPDF must display Appropriate Legal Notices, as required
# under Section 5 of the GNU Affero General Public License version 3.
#
# In accordance with Section 7(b) of the GNU Affero General Public
# License, a covered work must retain the producer line in every PDF that
# is created or manipulated using HexaPDF.
#++

require 'fiber'
require 'strscan'
require 'hexapdf/error'

module HexaPDF
  module Filter

    # Implements the run length filter.
    #
    # See: HexaPDF::Filter, PDF1.7 s7.4.5
    module RunLengthDecode

      EOD = 128.chr #:nodoc:

      # See HexaPDF::Filter
      def self.decoder(source, _ = nil)
        Fiber.new do
          i = 0
          result = ''.b
          data = source.resume
          while data && i < data.length
            length = data.getbyte(i)
            if length < 128 && i + length + 1 < data.length # no byte run and enough bytes
              result << data[i + 1, length + 1]
              i += length + 2
            elsif length > 128 && i + 1 < data.length # byte run and enough bytes
              result << data[i + 1] * (257 - length)
              i += 2
            elsif length != 128 # not enough bytes in data
              Fiber.yield(result)
              if source.alive? && (new_data = source.resume)
                data = data[i..-1] << new_data
              else
                raise FilterError, "Missing data for run length encoded stream"
              end
              i = 0
              result = ''.b
            else # EOD reached
              break
            end

            if i == data.length && source.alive? && (data = source.resume)
              Fiber.yield(result)
              i = 0
              result = ''.b
            end
          end
          result unless result.empty?
        end
      end

      # See HexaPDF::Filter
      def self.encoder(source, _ = nil)
        Fiber.new do
          while source.alive? && (data = source.resume)
            result = ''.b
            strscan = StringScanner.new(data)
            until strscan.eos?
              if strscan.scan(/(.)\1{1,127}/m) # a run of <= 128 same characters
                result << (257 - strscan.matched_size).chr << strscan[1]
              else # a run of characters until two same characters or length > 128
                match = strscan.scan(/.{1,128}?(?=(.)\1|\z)|.{128}/m)
                result << (match.length - 1).chr << match
              end
            end
            Fiber.yield(result)
          end
          EOD
        end
      end

    end

  end
end
