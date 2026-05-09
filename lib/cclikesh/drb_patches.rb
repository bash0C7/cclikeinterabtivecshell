# frozen_string_literal: true

require "drb/drb"

# DRb::DRbObject inherits Kernel#display, which writes self to $stdout and
# returns nil. That shadows method_missing-based remote dispatch, so a remote
# call to `display` would silently print the proxy and return nil instead of
# invoking the real remote method. Undef it so DRbObject only relies on
# method_missing for routing.
class DRb::DRbObject
  undef_method :display if method_defined?(:display) || private_method_defined?(:display)
end
