-- ReaTC LTC decoder

return function(core)
  local M = {}
  local s = core.state

  local _sbuf      = nil   -- reaper.array, allocated once
  local _sbuf_size = 0

  local function push_bit(b)
    s.bit_idx = s.bit_idx + 1
    s.bit_buf[((s.bit_idx - 1) & 511) + 1] = b

    if b == 1 then
      s.bit_ones = s.bit_ones + 1
    else
      s.bit_zeros = s.bit_zeros + 1
    end

    if s.bit_idx < 80 then return end

    local word_lsb = 0
    local word_msb = 0
    for i = 0, 15 do
      local idx = (((s.bit_idx - 16 + i) & 511) + 1)
      local bit_val = s.bit_buf[idx]
      word_lsb = word_lsb | (bit_val << i)
      word_msb = word_msb | (bit_val << (15 - i))
    end

    local found_sync = false
    if word_lsb == 0x3FFD or word_lsb == 0xBFFC then
      found_sync = true
      s.last_sync_word = word_lsb
    elseif word_msb == 0x3FFD or word_msb == 0xBFFC then
      found_sync = true
      s.last_sync_word = word_msb
    end

    if found_sync then
      s.sync_count = s.sync_count + 1
      local start = s.bit_idx - 80

      local function eb(offset, count)
        local r = 0
        for i = 0, count - 1 do
          local idx = (((start + offset + i) & 511) + 1)
          r = r | (s.bit_buf[idx] << i)
        end
        return r
      end

      local f_u = eb(0, 4);  local f_t = eb(8, 2)
      local s_u = eb(16, 4); local s_t = eb(24, 3)
      local m_u = eb(32, 4); local m_t = eb(40, 3)
      local h_u = eb(48, 4); local h_t = eb(56, 2)

      local fr = f_t * 10 + f_u
      local sr = s_t * 10 + s_u
      local mr = m_t * 10 + m_u
      local hr = h_t * 10 + h_u

      local fps_int = core.FPS_INT[s.framerate_type + 1]
      if fr < fps_int and sr < 60 and mr < 60 and hr < 24 then
        s.tc_h, s.tc_m, s.tc_s, s.tc_f = hr, mr, sr, fr
        s.tc_type  = s.framerate_type
        s.tc_valid = true
        s.last_valid_time = reaper.time_precise()
      end
    end
  end

  function M.decode_ltc_chunk()
    local track = s.ltc_track
    if not track then return end

    if not s.accessor then
      s.accessor     = reaper.CreateTrackAudioAccessor(track)
      s.last_read_pos = math.max(0, reaper.GetPlayPosition() - 0.1)
    end

    local cur_pos = reaper.GetPlayPosition()
    local window  = cur_pos - s.last_read_pos

    if window < -0.5 then
      s.last_read_pos = cur_pos - 0.05
      s.tc_valid = false
      return
    end
    if window < 0.005 then return end

    local nsamples = math.min(math.floor(window * core.DECODER_SRATE), 4096)
    if nsamples < 1 then return end

    if _sbuf_size < nsamples then
      _sbuf      = reaper.new_array(nsamples)
      _sbuf_size = nsamples
    end

    reaper.GetAudioAccessorSamples(s.accessor, core.DECODER_SRATE, 1,
                                    s.last_read_pos, nsamples, _sbuf)
    s.last_read_pos = s.last_read_pos + nsamples / core.DECODER_SRATE

    local fps = core.FPS_INT[s.framerate_type + 1]
    local spb  = core.DECODER_SRATE / (fps * 80)
    local thr  = 10 ^ (s.threshold_db / 20)
    local mid  = spb * 0.75
    local minb = spb * 0.25
    local maxb = spb * 1.5

    local sig_state          = s.sig_state
    local bpm_state          = s.bpm_state
    local samples_since_trans = s.samples_since_trans
    local last_gap           = s.last_gap

    for i = 1, nsamples do
      local spl = _sbuf[i]
      samples_since_trans = samples_since_trans + 1

      local abs_spl = math.abs(spl)
      if abs_spl > s.peak_level then
        s.peak_level = abs_spl
      end

      local ns = 0
      if spl > thr then ns = 1 elseif spl < -thr then ns = -1 end

      if ns ~= 0 and ns ~= sig_state then
        sig_state = ns
        s.trans_count = s.trans_count + 1
        local gap = samples_since_trans
        samples_since_trans = 0

        if gap < minb then
          bpm_state = 0
        elseif gap < mid then
          last_gap = gap
          if bpm_state == 0 then
            bpm_state = 1
          else
            push_bit(1)
            bpm_state = 0
          end
        elseif gap < maxb then
          last_gap = gap
          if bpm_state == 0 then
            push_bit(0)
          else
            push_bit(1)
            bpm_state = 0
          end
        else
          bpm_state = 0
        end
      end
    end

    s.sig_state           = sig_state
    s.bpm_state           = bpm_state
    s.samples_since_trans = samples_since_trans
    s.last_gap            = last_gap

    s.peak_level = s.peak_level * 0.95
  end

  function M.destroy_accessor()
    if s.accessor then
      reaper.DestroyAudioAccessor(s.accessor)
      s.accessor = nil
    end
  end

  return M
end
