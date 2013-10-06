module Tracks
  # Includes +task_for+ into the host class (e.g. an abstract controller or mailer). The class
  # has to provide a +TaskSet+ by implementing the <tt>_tasks</tt> methods. Otherwise, an
  # exception will be raised.
  #
  # Note that this module is completely decoupled from HTTP - the only requirement is a valid
  # <tt>_tasks</tt> implementation.
  module TaskFor
  end
end
