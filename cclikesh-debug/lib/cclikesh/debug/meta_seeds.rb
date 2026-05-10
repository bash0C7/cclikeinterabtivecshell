module Cclikesh
  module Debug
    module MetaSeeds
      ROWS = [
        ["db",     "cclikesh_debug",        "cclikesh debug session — frame log + sqlite-vec semantic", nil, nil, nil],
        ["table",  "frames",                "one row per captured frame", nil, nil, nil],
        ["table",  "session_info",          "session metadata (1 row per file)", nil, nil, nil],
        ["table",  "frame_vec",             "vec0 virtual table mapping frame_id → 768-dim embedding", nil, nil, nil],
        ["column", "frames.content",        "framework_state-derived visible text, embed target", nil, nil, nil],
        ["column", "frames.source",         "always 'framework_state' (chiebukuro-mcp compat)", nil, nil, nil],
        ["column", "frames.event_kind",     "nullable; tag for event-driven frames", nil, nil, nil],
        ["column", "frames.framework_state_json", "JSON snapshot of cclikesh framework state", nil, nil, nil],
        ["recipe", "popup_active",
         "frames with popup active",
         nil,
         "SELECT id, ts FROM frames WHERE json_extract(framework_state_json,'$.popup.active')=1 ORDER BY ts",
         "frames with popup active"],
        ["recipe", "latest",
         "latest 50 frames",
         nil,
         "SELECT id, ts, event_kind, content FROM frames ORDER BY ts DESC LIMIT 50",
         "latest 50 frames"],
        ["recipe", "phase_working",
         "frames during :working phase",
         nil,
         "SELECT id, ts, content FROM frames WHERE json_extract(framework_state_json,'$.phase')='working' ORDER BY ts",
         "frames during :working phase"]
      ].freeze
    end
  end
end
