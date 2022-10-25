module Idv
  module Actions
    class CancelUpdateSsnAction < Idv::Steps::DocAuthBaseStep
      def self.analytics_submitted_event
        :idv_doc_auth_cancel_update_ssn_submitted
      end

      def call
        mark_step_complete(:ssn) if flow_session.dig(:pii_from_doc, :ssn)
      end
    end
  end
end
