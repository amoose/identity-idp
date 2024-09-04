require 'rails_helper'

RSpec.shared_examples 'enrollment_with_a_status_update' do |passed:,
                                                            email_type:,
                                                            enrollment_status:,
                                                            response_json:,
                                                            enhanced_ipp_enrollment: false|

  it 'logs an enrollment status update analytics event' do
    date_far_from_daylight_savings_changes = Time.zone.parse('2023-11-30T10:00:00Z')
    travel_to date_far_from_daylight_savings_changes do
      pending_enrollment.update(
        enrollment_established_at: Time.zone.now - 3.days,
        status_check_attempted_at: Time.zone.now - 15.minutes,
        status_check_completed_at: Time.zone.now - 17.minutes,
        status_updated_at: Time.zone.now - 2.days,
      )
      job.perform(Time.zone.now)

      response = JSON.parse(response_json)
      expect(job_analytics).to have_logged_event(
        'GetUspsProofingResultsJob: Enrollment status updated',
        hash_including(
          {
            assurance_level: response['assuranceLevel'],
            enrollment_code: pending_enrollment.enrollment_code,
            enrollment_id: pending_enrollment.id,
            failure_reason: response['failureReason'],
            fraud_suspected: response['fraudSuspected'],
            issuer: pending_enrollment.issuer,
            minutes_since_last_status_check: 15.0,
            minutes_since_last_status_check_completed: 17.0,
            minutes_since_last_status_update: 2.days.in_minutes,
            minutes_to_completion: 3.days.in_minutes,
            minutes_since_established: 3.days.in_minutes,
            passed: passed,
            primary_id_type: response['primaryIdType'],
            proofing_city: response['proofingCity'],
            proofing_post_office: response['proofingPostOffice'],
            proofing_state: response['proofingState'],
            reason: anything,
            response_message: response['responseMessage'],
            response_present: true,
            scan_count: response['scanCount'],
            secondary_id_type: response['secondaryIdType'],
            status: response['status'],
            job_name: 'GetUspsProofingResultsJob',
            tmx_status: :threatmetrix_pass,
            profile_age_in_seconds: instance_of(Integer),
            enhanced_ipp: enhanced_ipp_enrollment,
          }.compact,
        ),
      )
    end
  end

  it 'logs message with email analytics attributes' do
    freeze_time do
      job.perform(Time.zone.now)
      if email_type == 'deadline passed'
        expect(job_analytics).to have_logged_event(
          'GetUspsProofingResultsJob: deadline passed email initiated',
          hash_including(
            {
              enrollment_code: pending_enrollment.enrollment_code,
              enrollment_id: pending_enrollment.id,
              service_provider: pending_enrollment.issuer,
              timestamp: Time.zone.now,
              job_name: 'GetUspsProofingResultsJob',
            }.compact,
          ),
        )
      else
        expect(job_analytics).to have_logged_event(
          'GetUspsProofingResultsJob: Success or failure email initiated',
          hash_including(
            {
              email_type: email_type,
              enrollment_code: pending_enrollment.enrollment_code,
              service_provider: pending_enrollment.issuer,
              timestamp: Time.zone.now,
              job_name: 'GetUspsProofingResultsJob',
            }.compact,
          ),
        )
      end
    end
  end

  it 'updates the status of the enrollment and profile appropriately' do
    freeze_time do
      pending_enrollment.update(
        status_check_attempted_at: Time.zone.now - 1.day,
        status_updated_at: Time.zone.now - 2.days,
      )
      job.perform(Time.zone.now)

      pending_enrollment.reload
      expect(pending_enrollment.status_updated_at).to eq(Time.zone.now)
      expect(pending_enrollment.status_check_attempted_at).to eq(Time.zone.now)
      expect(pending_enrollment.status_check_completed_at).to eq(Time.zone.now)
      expect(pending_enrollment.status).to eq(enrollment_status)
      expect(pending_enrollment.profile.active).to eq(passed)
    end
  end
end

RSpec.shared_examples 'enrollment_encountering_an_exception' do |exception_class: nil,
                                                                exception_message: nil,
                                                                reason: 'Request exception',
                                                                response_message: nil,
                                                                response_status_code: nil|
  it 'logs an error message and leaves the enrollment and profile pending' do
    job.perform(Time.zone.now)
    pending_enrollment.reload

    expect(pending_enrollment.pending?).to eq(true)
    expect(pending_enrollment.profile.active).to eq(false)
    expect(job_analytics).to have_logged_event(
      'GetUspsProofingResultsJob: Exception raised',
      hash_including(
        {
          enrollment_code: pending_enrollment.enrollment_code,
          enrollment_id: pending_enrollment.id,
          exception_class: exception_class,
          exception_message: exception_message,
          reason: reason,
          response_message: response_message,
          response_status_code: response_status_code,
          job_name: 'GetUspsProofingResultsJob',
        }.compact,
      ),
    )
  end

  it 'updates the status_check_attempted_at timestamp' do
    freeze_time do
      pending_enrollment.update(
        status_check_attempted_at: Time.zone.now - 1.day,
        status_updated_at: Time.zone.now - 2.days,
      )
      job.perform(Time.zone.now)

      pending_enrollment.reload
      expect(pending_enrollment.status_updated_at).to eq(Time.zone.now - 2.days)
      expect(pending_enrollment.status_check_attempted_at).to eq(Time.zone.now)
    end
  end

  it 'does not update the status_check_completed_at timestamp' do
    freeze_time do
      pending_enrollment.update(
        status_check_attempted_at: Time.zone.now - 1.day,
        status_updated_at: Time.zone.now - 2.days,
      )
      job.perform(Time.zone.now)

      pending_enrollment.reload
      expect(pending_enrollment.status_updated_at).to eq(Time.zone.now - 2.days)
      expect(pending_enrollment.status_check_completed_at).to be_nil
    end
  end
end

RSpec.shared_examples 'enrollment_encountering_an_error_that_has_a_nil_response' do |error_type:|
  it 'logs that response is not present' do
    expect(NewRelic::Agent).to receive(:notice_error).
      with(instance_of(error_type)).at_least(1).times
    job.perform(Time.zone.now)

    expect(job_analytics).to have_logged_event(
      'GetUspsProofingResultsJob: Exception raised',
      hash_including(
        reason: 'Request exception',
        response_present: false,
        exception_class: error_type.to_s,
        job_name: 'GetUspsProofingResultsJob',
      ),
    )
  end

  it 'does not update the status_check_completed_at timestamp' do
    freeze_time do
      job.perform(Time.zone.now)
      pending_enrollment.reload
      expect(pending_enrollment.status_check_completed_at).to be_nil
    end
  end
end

RSpec.describe GetUspsProofingResultsJob, allowed_extra_analytics: [:*] do
  include UspsIppHelper
  include ApproximatingHelper

  let(:reprocess_delay_minutes) { 2.0 }
  let(:request_delay_ms) { 0 }
  let(:job) { GetUspsProofingResultsJob.new }
  let(:job_analytics) { FakeAnalytics.new }
  let(:transaction_start_date_time) do
    ActiveSupport::TimeZone[-6].strptime(
      '12/17/2020 033855',
      '%m/%d/%Y %H%M%S',
    ).in_time_zone('UTC')
  end
  let(:transaction_end_date_time) do
    ActiveSupport::TimeZone[-6].strptime(
      '12/17/2020 034055',
      '%m/%d/%Y %H%M%S',
    ).in_time_zone('UTC')
  end
  let(:in_person_proofing_enforce_tmx) { true }
  let(:usps_ipp_sponsor_id) { '12345' }
  let(:usps_eipp_sponsor_id) { '98765' }

  before do
    allow(IdentityConfig.store).
      to(receive(:in_person_results_delay_in_hours).and_return(nil))
    allow(IdentityConfig.store).to receive(:usps_mock_fallback).
      and_return(false)
    allow(Rails).to receive(:cache).and_return(
      ActiveSupport::Cache::RedisCacheStore.new(url: IdentityConfig.store.redis_throttle_url),
    )
    ActiveJob::Base.queue_adapter = :test
    allow(job).to receive(:analytics).and_return(job_analytics)
    allow(IdentityConfig.store).to receive(:get_usps_proofing_results_job_reprocess_delay_minutes).
      and_return(reprocess_delay_minutes)
    allow(IdentityConfig.store).to receive(:in_person_proofing_enforce_tmx).
      and_return(in_person_proofing_enforce_tmx)
    allow(IdentityConfig.store).to receive(:in_person_enrollments_ready_job_enabled).
      and_return(false)
    allow(IdentityConfig.store).to receive(:usps_ipp_sponsor_id).and_return(usps_ipp_sponsor_id)
    allow(IdentityConfig.store).to receive(:usps_eipp_sponsor_id).and_return(usps_eipp_sponsor_id)
    stub_const(
      'GetUspsProofingResultsJob::REQUEST_DELAY_IN_SECONDS',
      request_delay_ms / GetUspsProofingResultsJob::MILLISECONDS_PER_SECOND,
    )
    stub_request_token
    if respond_to?(:pending_enrollment)
      pending_enrollment.update(enrollment_established_at: 3.days.ago)
    end
  end

  describe '#perform' do
    describe 'IPP enabled' do
      describe 'In-Person Proofing' do
        describe 'Proofed without secondary id' do
          let!(:pending_enrollments) do
            ['BALTIMORE', 'FRIENDSHIP', 'WASHINGTON', 'ARLINGTON', 'DEANWOOD'].map do |name|
              create(
                :in_person_enrollment,
                :pending,
                :with_notification_phone_configuration,
                issuer: 'http://localhost:3000',
                selected_location_details: { name: name },
                sponsor_id: usps_ipp_sponsor_id,
              )
            end
          end
          let(:pending_enrollment) { pending_enrollments.first }

          before do
            enrollment_records = InPersonEnrollment.where(id: pending_enrollments.map(&:id))
            allow(InPersonEnrollment).to receive(:needs_usps_status_check).
              and_return(enrollment_records)
            allow(IdentityConfig.store).to receive(:in_person_proofing_enabled).and_return(true)
          end

          it 'requests the enrollments that need their status checked' do
            stub_request_passed_proofing_results

            freeze_time do
              job.perform(Time.zone.now)

              expect(InPersonEnrollment).to(
                have_received(:needs_usps_status_check).
                with(...reprocess_delay_minutes.minutes.ago),
              )
            end
          end

          it 'records the last attempted status check regardless of response code and contents' do
            enrollment_records = InPersonEnrollment.where(id: pending_enrollments.map(&:id))
            allow(InPersonEnrollment).to receive(:needs_usps_status_check).
              and_return(enrollment_records)
            stub_request_proofing_results_with_responses(
              request_failed_proofing_results_args,
              request_in_progress_proofing_results_args,
              request_in_progress_proofing_results_args,
              request_failed_proofing_results_args,
            )

            expect(pending_enrollments.pluck(:status_check_attempted_at)).to(
              all(eq nil),
              'failed test precondition:
              pending enrollments must not set status check attempted time',
            )

            expect(pending_enrollments.pluck(:status_check_completed_at)).to(
              all(eq nil),
              'failed test precondition:
              pending enrollments must not set status check completed time',
            )

            freeze_time do
              job.perform(Time.zone.now)

              expect(
                pending_enrollments.
                  map(&:reload).
                  pluck(:status_check_attempted_at),
              ).to(
                all(eq Time.zone.now),
                'job must update status check attempted time for all pending enrollments',
              )

              expect(
                pending_enrollments.
                  map(&:reload).
                  pluck(:status_check_completed_at),
              ).to(
                all(eq Time.zone.now),
                'job must update status check completed time for all pending enrollments',
              )
            end
          end

          it 'logs a message when the job starts' do
            enrollment_records = InPersonEnrollment.where(id: pending_enrollments.map(&:id))
            allow(InPersonEnrollment).to receive(:needs_usps_status_check).
              and_return(enrollment_records)
            stub_request_proofing_results_with_responses(
              request_failed_proofing_results_args,
              request_in_progress_proofing_results_args,
              request_in_progress_proofing_results_args,
              request_failed_proofing_results_args,
            )

            job.perform(Time.zone.now)

            expect(job_analytics).to have_logged_event(
              'GetUspsProofingResultsJob: Job started',
              enrollments_count: 5,
              reprocess_delay_minutes: 2.0,
              job_name: 'GetUspsProofingResultsJob',
            )
          end

          it <<~STR.squish do
            logs a message with counts of various outcomes when the job
            completes (errored > 0)
          STR
            pending_enrollments.append(
              create(
                :in_person_enrollment, :pending,
                selected_location_details: { name: 'DEANWOOD' }
              ),
              create(
                :in_person_enrollment, :pending,
                selected_location_details: { name: 'DEANWOOD' }
              ),
            )
            enrollment_records = InPersonEnrollment.where(id: pending_enrollments.map(&:id))
            allow(InPersonEnrollment).to receive(:needs_usps_status_check).
              and_return(enrollment_records)
            stub_request_proofing_results_with_responses(
              request_passed_proofing_results_args,
              request_in_progress_proofing_results_args,
              { status: 500 },
              request_failed_proofing_results_args,
              request_expired_id_ipp_results_args,
            ).and_raise(Faraday::TimeoutError).and_raise(Faraday::ConnectionFailed)

            job.perform(Time.zone.now)

            expect(job_analytics).to have_logged_event(
              'GetUspsProofingResultsJob: Job completed',
              duration_seconds: anything,
              enrollments_checked: 7,
              enrollments_errored: 1,
              enrollments_network_error: 2,
              enrollments_expired: 1,
              enrollments_failed: 1,
              enrollments_in_progress: 1,
              enrollments_passed: 1,
              percent_enrollments_errored: 14.29,
              percent_enrollments_network_error: 28.57,
              job_name: 'GetUspsProofingResultsJob',
            )

            expect(
              job_analytics.events['GetUspsProofingResultsJob: Job completed'].
                first[:duration_seconds],
            ).to be >= 0.0
          end

          it <<~STR.squish do
            logs a message with counts of various
            outcomes when the job completes (errored = 0)
          STR
            enrollment_records = InPersonEnrollment.where(id: pending_enrollments.map(&:id))
            allow(InPersonEnrollment).to receive(:needs_usps_status_check).
              and_return(enrollment_records)
            stub_request_proofing_results_with_responses(
              request_passed_proofing_results_args,
            )

            job.perform(Time.zone.now)

            expect(job_analytics).to have_logged_event(
              'GetUspsProofingResultsJob: Job completed',
              duration_seconds: anything,
              enrollments_checked: 5,
              enrollments_errored: 0,
              enrollments_network_error: 0,
              enrollments_expired: 0,
              enrollments_failed: 0,
              enrollments_in_progress: 0,
              enrollments_passed: 5,
              percent_enrollments_errored: 0.00,
              percent_enrollments_network_error: 0.00,
              job_name: 'GetUspsProofingResultsJob',
            )

            expect(
              job_analytics.events['GetUspsProofingResultsJob: Job completed'].
                first[:duration_seconds],
            ).to be >= 0.0
          end

          it 'logs a message with counts of various outcomes when the job completes
          (no enrollments)' do
            allow(InPersonEnrollment).to receive(:needs_usps_status_check).
              and_return(InPersonEnrollment.none)
            stub_request_proofing_results_with_responses(
              request_passed_proofing_results_args,
            )

            job.perform(Time.zone.now)

            expect(job_analytics).to have_logged_event(
              'GetUspsProofingResultsJob: Job completed',
              duration_seconds: anything,
              enrollments_checked: 0,
              enrollments_errored: 0,
              enrollments_network_error: 0,
              enrollments_expired: 0,
              enrollments_failed: 0,
              enrollments_in_progress: 0,
              enrollments_passed: 0,
              percent_enrollments_errored: 0.00,
              percent_enrollments_network_error: 0.00,
              job_name: 'GetUspsProofingResultsJob',
            )

            expect(
              job_analytics.events['GetUspsProofingResultsJob: Job completed'].
                first[:duration_seconds],
            ).to be >= 0.0
          end

          context 'a standard error is raised when requesting proofing results' do
            let(:error_message) { 'A standard error happened' }
            let!(:error) { StandardError.new(error_message) }
            let!(:proofer) { described_class.new }

            it 'logs failure details' do
              allow(UspsInPersonProofing::Proofer).to receive(:new).and_return(proofer)
              allow(proofer).to receive(:request_proofing_results).and_raise(error)
              expect(NewRelic::Agent).to receive(:notice_error).with(error).at_least(1).times

              job.perform(Time.zone.now)

              expect(job_analytics).to have_logged_event(
                'GetUspsProofingResultsJob: Exception raised',
                hash_including(
                  exception_message: error_message,
                  exception_class: 'StandardError',
                  reason: 'Request exception',
                  job_name: 'GetUspsProofingResultsJob',
                ),
              )
            end
          end

          context 'with a request delay in ms' do
            let(:request_delay_ms) { 750 }

            it 'adds a delay between requests to USPS' do
              enrollment_records = InPersonEnrollment.where(id: pending_enrollments.map(&:id))
              allow(InPersonEnrollment).to receive(:needs_usps_status_check).
                and_return(enrollment_records)
              stub_request_passed_proofing_results
              expect(job).to receive(:sleep).exactly(pending_enrollments.length - 1).times.
                with(0.75)

              job.perform(Time.zone.now)
            end
          end

          context 'when an enrollment does not have a unique ID' do
            it 'generates a backwards-compatible unique ID' do
              pending_enrollment.update(unique_id: nil)
              stub_request_passed_proofing_results
              expect_any_instance_of(InPersonEnrollment).to receive(
                :usps_unique_id,
              ).and_call_original

              job.perform(Time.zone.now)
              pending_enrollment.reload
              expect(pending_enrollment.unique_id).not_to be_nil
            end
          end

          describe 'sending emails' do
            it 'sends proofing failed email on response with failed status' do
              stub_request_failed_proofing_results

              user = pending_enrollment.user

              freeze_time do
                expect do
                  job.perform(Time.zone.now)
                end.to have_enqueued_mail(UserMailer, :in_person_failed).with(
                  params: { user: user, email_address: user.email_addresses.first },
                  args: [{ enrollment: pending_enrollment }],
                )
              end
            end

            it 'sends deadline passed email on response with expired status' do
              stub_request_expired_id_ipp_proofing_results
              user = pending_enrollment.user
              expect(pending_enrollment.deadline_passed_sent).to be false
              freeze_time do
                expect do
                  job.perform(Time.zone.now)
                end.to have_enqueued_mail(UserMailer, :in_person_deadline_passed).with(
                  params: { user: user, email_address: user.email_addresses.first },
                  args: [{ enrollment: pending_enrollment }],
                ).at(:no_wait).on_queue(:default)
                pending_enrollment.reload
                expect(pending_enrollment.deadline_passed_sent).to be true
                expect(job_analytics).to have_logged_event(
                  'GetUspsProofingResultsJob: deadline passed email initiated',
                  enrollment_code: pending_enrollment.enrollment_code,
                  enrollment_id: pending_enrollment.id,
                  service_provider: pending_enrollment.issuer,
                  timestamp: anything,
                  job_name: 'GetUspsProofingResultsJob',
                )
              end
            end

            it 'sends failed email when fraudSuspected is true' do
              stub_request_failed_suspected_fraud_proofing_results

              user = pending_enrollment.user

              freeze_time do
                expect do
                  job.perform(Time.zone.now)
                end.to have_enqueued_mail(UserMailer, :in_person_failed_fraud).with(
                  params: { user: user, email_address: user.email_addresses.first },
                  args: [{ enrollment: pending_enrollment }],
                )
              end
            end

            it 'sends proofing verifed email on 2xx responses with valid JSON' do
              stub_request_passed_proofing_results

              user = pending_enrollment.user

              freeze_time do
                expect do
                  job.perform(Time.zone.now)
                end.to have_enqueued_mail(UserMailer, :in_person_verified).with(
                  params: { user: user, email_address: user.email_addresses.first },
                  args: [{ enrollment: pending_enrollment }],
                )
              end
            end

            context 'a custom delay greater than zero is set' do
              let(:user) { pending_enrollment.user }
              let(:proofed_at_string) do
                proofed_at = ActiveSupport::TimeZone[-6].now
                proofed_at.strftime('%m/%d/%Y %H%M%S')
              end

              before do
                allow(IdentityConfig.store).
                  to(receive(:in_person_results_delay_in_hours).and_return(5))
              end

              it 'uses the custom delay when proofing passes' do
                wait_until = nil

                freeze_time do
                  stub_request_passed_proofing_results(transactionEndDateTime: proofed_at_string)
                  wait_until = Time.zone.now +
                               IdentityConfig.store.in_person_results_delay_in_hours.hours
                  expect do
                    job.perform(Time.zone.now)
                  end.to have_enqueued_mail(UserMailer, :in_person_verified).with(
                    params: { user: user, email_address: user.email_addresses.first },
                    args: [{ enrollment: pending_enrollment }],
                  ).at(wait_until).on_queue(:intentionally_delayed)
                end

                expect(job_analytics).to have_logged_event(
                  'GetUspsProofingResultsJob: Success or failure email initiated',
                  email_type: 'Success',
                  enrollment_code: pending_enrollment.enrollment_code,
                  service_provider: anything,
                  timestamp: anything,
                  wait_until: wait_until,
                  job_name: 'GetUspsProofingResultsJob',
                )
              end

              it 'uses the custom delay when proofing fails' do
                wait_until = nil

                freeze_time do
                  stub_request_failed_proofing_results(transactionEndDateTime: proofed_at_string)
                  wait_until = Time.zone.now +
                               IdentityConfig.store.in_person_results_delay_in_hours.hours
                  expect do
                    job.perform(Time.zone.now)
                  end.to have_enqueued_mail(UserMailer, :in_person_failed).with(
                    params: { user: user, email_address: user.email_addresses.first },
                    args: [{ enrollment: pending_enrollment }],
                  ).at(wait_until).on_queue(:intentionally_delayed)
                end

                expect(job_analytics).to have_logged_event(
                  'GetUspsProofingResultsJob: Success or failure email initiated',
                  email_type: 'Failed',
                  enrollment_code: pending_enrollment.enrollment_code,
                  service_provider: anything,
                  timestamp: anything,
                  wait_until: wait_until,
                  job_name: 'GetUspsProofingResultsJob',
                )
              end
            end

            context 'a custom delay of zero is set' do
              it 'does not delay sending the email' do
                stub_request_passed_proofing_results

                allow(IdentityConfig.store).
                  to(receive(:in_person_results_delay_in_hours).and_return(0))
                user = pending_enrollment.user

                expect do
                  job.perform(Time.zone.now)
                end.to have_enqueued_mail(UserMailer, :in_person_verified).with(
                  params: { user: user, email_address: user.email_addresses.first },
                  args: [{ enrollment: pending_enrollment }],
                ).at(:no_wait).on_queue(:default)
              end
            end
          end

          context 'when an enrollment passes' do
            before(:each) do
              stub_request_passed_proofing_results
            end

            it_behaves_like(
              'enrollment_with_a_status_update',
              passed: true,
              email_type: 'Success',
              enrollment_status: InPersonEnrollment::STATUS_PASSED,
              response_json: UspsInPersonProofing::Mock::Fixtures.
                request_passed_proofing_results_response,
            )

            it 'invokes the SendProofingNotificationJob and logs details about the success' do
              allow(IdentityConfig.store).to receive(
                :in_person_send_proofing_notifications_enabled,
              ).and_return(true)
              expected_wait_until = nil
              freeze_time do
                expected_wait_until = 1.hour.from_now
                expect do
                  job.perform(Time.zone.now)
                  pending_enrollment.reload
                end.to have_enqueued_job(InPerson::SendProofingNotificationJob).
                  with(pending_enrollment.id).at(
                    expected_wait_until,
                  ).on_queue(:intentionally_delayed)
              end

              expect(pending_enrollment.proofed_at).to eq(transaction_end_date_time)
              expect(job_analytics).to have_logged_event(
                'GetUspsProofingResultsJob: Enrollment status updated',
                hash_including(
                  reason: 'Successful status update',
                  passed: true,
                  job_name: 'GetUspsProofingResultsJob',
                  enhanced_ipp: false,
                ),
              )
              expect(job_analytics).to have_logged_event(
                'GetUspsProofingResultsJob: Success or failure email initiated',
                email_type: 'Success',
                enrollment_code: pending_enrollment.enrollment_code,
                service_provider: anything,
                timestamp: anything,
                wait_until: expected_wait_until,
                job_name: 'GetUspsProofingResultsJob',
              )
            end
          end

          context 'when an enrollment fails' do
            before(:each) do
              stub_request_failed_proofing_results
            end

            it_behaves_like(
              'enrollment_with_a_status_update',
              passed: false,
              email_type: 'Failed',
              enrollment_status: InPersonEnrollment::STATUS_FAILED,
              response_json: UspsInPersonProofing::Mock::Fixtures.
                request_failed_proofing_results_response,
            )

            it 'logs failure details' do
              expected_wait_until = nil
              freeze_time do
                expected_wait_until = 1.hour.from_now
                job.perform(Time.zone.now)
              end

              pending_enrollment.reload
              expect(pending_enrollment.proofed_at).to eq(transaction_end_date_time)
              expect(job_analytics).to have_logged_event(
                'GetUspsProofingResultsJob: Enrollment status updated',
                hash_including(
                  passed: false,
                  reason: 'Failed status',
                  job_name: 'GetUspsProofingResultsJob',
                  enhanced_ipp: false,
                ),
              )
              expect(job_analytics).to have_logged_event(
                'GetUspsProofingResultsJob: Success or failure email initiated',
                email_type: 'Failed',
                enrollment_code: pending_enrollment.enrollment_code,
                service_provider: anything,
                timestamp: anything,
                wait_until: expected_wait_until,
                job_name: 'GetUspsProofingResultsJob',
              )
            end
          end

          context 'when an enrollment fails and fraud is suspected' do
            before(:each) do
              stub_request_failed_suspected_fraud_proofing_results
            end

            it_behaves_like(
              'enrollment_with_a_status_update',
              passed: false,
              email_type: 'Failed fraud suspected',
              enrollment_status: InPersonEnrollment::STATUS_FAILED,
              response_json: UspsInPersonProofing::Mock::Fixtures.
                request_failed_suspected_fraud_proofing_results_response,
            )

            it 'logs fraud failure details' do
              expected_wait_until = nil
              freeze_time do
                expected_wait_until = 1.hour.from_now
                job.perform(Time.zone.now)
              end

              pending_enrollment.reload
              expect(pending_enrollment.proofed_at).to eq(transaction_end_date_time)
              expect(job_analytics).to have_logged_event(
                'GetUspsProofingResultsJob: Enrollment status updated',
                hash_including(
                  fraud_suspected: true,
                  passed: false,
                  reason: 'Failed status',
                  job_name: 'GetUspsProofingResultsJob',
                  enhanced_ipp: false,
                ),
              )
              expect(job_analytics).to have_logged_event(
                'GetUspsProofingResultsJob: Success or failure email initiated',
                email_type: 'Failed fraud suspected',
                enrollment_code: pending_enrollment.enrollment_code,
                service_provider: anything,
                timestamp: anything,
                wait_until: expected_wait_until,
                job_name: 'GetUspsProofingResultsJob',
              )
            end
          end

          context 'when an enrollment passes proofing with an unsupported ID' do
            before(:each) do
              stub_request_passed_proofing_unsupported_id_results
            end

            it_behaves_like(
              'enrollment_with_a_status_update',
              passed: false,
              email_type: 'Failed unsupported ID type',
              enrollment_status: InPersonEnrollment::STATUS_FAILED,
              response_json: UspsInPersonProofing::Mock::Fixtures.
                request_passed_proofing_unsupported_id_results_response,
            )

            it 'deactivates the associated profile' do
              expect(pending_enrollment.profile.in_person_verification_pending_at).not_to be_nil
              job.perform Time.zone.now
              pending_enrollment.reload

              expect(pending_enrollment.profile.in_person_verification_pending_at).to be_nil
              expect(pending_enrollment.profile.active).to be false
              expect(pending_enrollment.profile.deactivation_reason).to eq('verification_cancelled')
            end

            it 'logs a message about the unsupported ID' do
              expected_wait_until = nil
              freeze_time do
                expected_wait_until = 1.hour.from_now
                job.perform Time.zone.now
              end

              pending_enrollment.reload
              expect(pending_enrollment.proofed_at).to eq(transaction_end_date_time)
              expect(job_analytics).to have_logged_event(
                'GetUspsProofingResultsJob: Enrollment status updated',
                hash_including(
                  passed: false,
                  reason: 'Unsupported ID type',
                  job_name: 'GetUspsProofingResultsJob',
                  enhanced_ipp: false,
                ),
              )

              expect(job_analytics).to have_logged_event(
                'GetUspsProofingResultsJob: Success or failure email initiated',
                email_type: 'Failed unsupported ID type',
                enrollment_code: pending_enrollment.enrollment_code,
                service_provider: anything,
                timestamp: anything,
                wait_until: expected_wait_until,
                job_name: 'GetUspsProofingResultsJob',
              )
            end
          end

          context 'when an enrollment expires' do
            before(:each) do
              stub_request_expired_id_ipp_proofing_results
            end

            it_behaves_like(
              'enrollment_with_a_status_update',
              passed: false,
              email_type: 'deadline passed',
              enrollment_status: InPersonEnrollment::STATUS_EXPIRED,
              response_json: UspsInPersonProofing::Mock::Fixtures.
              request_expired_id_ipp_results_response,
            )

            it 'logs that the enrollment expired' do
              job.perform(Time.zone.now)

              expect(pending_enrollment.proofed_at).to eq(nil)
              expect(job_analytics).to have_logged_event(
                'GetUspsProofingResultsJob: Enrollment status updated',
                hash_including(
                  reason: 'Enrollment has expired',
                  job_name: 'GetUspsProofingResultsJob',
                  enhanced_ipp: false,
                ),
              )
            end

            it 'deactivates the associated profile' do
              expect(pending_enrollment.profile.in_person_verification_pending_at).not_to be_nil
              job.perform(Time.zone.now)

              pending_enrollment.reload
              expect(pending_enrollment.profile.active).to be false
              expect(pending_enrollment.profile.in_person_verification_pending_at).to be_nil
              expect(pending_enrollment.profile.deactivation_reason).to eq('verification_cancelled')
            end

            context 'when the in_person_stop_expiring_enrollments flag is true' do
              before do
                allow(IdentityConfig.store).to(
                  receive(:in_person_stop_expiring_enrollments).and_return(true),
                )
              end

              it 'treats the enrollment as incomplete' do
                job.perform(Time.zone.now)

                expect(pending_enrollment.status).to eq(InPersonEnrollment::STATUS_PENDING)
                # we pass the expiration message to analytics
                expect(job_analytics).to have_logged_event(
                  'GetUspsProofingResultsJob: Enrollment incomplete',
                  hash_including(
                    response_message: 'More than 30 days have passed since opt-in to IPP',
                    job_name: 'GetUspsProofingResultsJob',
                  ),
                )
              end

              it 'does not deactivate the profile' do
                job.perform(Time.zone.now)

                pending_enrollment.reload
                expect(pending_enrollment.profile.in_person_verification_pending_at).to_not be_nil
                expect(pending_enrollment.profile.deactivation_reason).to be_nil
              end
            end
          end

          context 'when an enrollment expires unexpectedly' do
            before(:each) do
              stub_request_unexpected_expired_proofing_results
            end

            it_behaves_like(
              'enrollment_with_a_status_update',
              passed: false,
              email_type: 'deadline passed',
              enrollment_status: InPersonEnrollment::STATUS_EXPIRED,
              response_json: UspsInPersonProofing::Mock::Fixtures.
                request_unexpected_expired_proofing_results_response,
            )

            it 'logs that the enrollment expired unexpectedly' do
              allow(IdentityConfig.store).to(
                receive(:in_person_enrollment_validity_in_days).and_return(30),
              )
              job.perform(Time.zone.now)

              expect(job_analytics).to have_logged_event(
                'GetUspsProofingResultsJob: Enrollment status updated',
                hash_including(
                  passed: false,
                  reason: 'Enrollment has expired',
                  job_name: 'GetUspsProofingResultsJob',
                  enhanced_ipp: false,
                ),
              )

              expect(job_analytics).to have_logged_event(
                'GetUspsProofingResultsJob: Unexpected response received',
                hash_including(
                  reason: 'Unexpected number of days before enrollment expired',
                  job_name: 'GetUspsProofingResultsJob',
                ),
              )
            end
          end

          context 'when an enrollment is reported as invalid' do
            context 'when an enrollment code is invalid' do
              # this enrollment code is hardcoded into the fixture
              # request_unexpected_invalid_enrollment_code_response.json
              let(:pending_enrollments) do
                [
                  create(:in_person_enrollment, :pending, enrollment_code: '1234567890123456'),
                ]
              end
              before(:each) do
                stub_request_unexpected_invalid_enrollment_code
              end

              it 'cancels the enrollment and logs that it was invalid' do
                job.perform(Time.zone.now)

                expect(pending_enrollment.reload.cancelled?).to be_truthy
                expect(job_analytics).to have_logged_event(
                  'GetUspsProofingResultsJob: Unexpected response received',
                  hash_including(
                    reason: 'Invalid enrollment code',
                    response_message: /Enrollment code [0-9]{16} does not exist/,
                    job_name: 'GetUspsProofingResultsJob',
                  ),
                )
              end

              it 'deactivates the associated profile' do
                expect(pending_enrollment.profile.in_person_verification_pending_at).not_to be_nil
                job.perform(Time.zone.now)
                pending_enrollment.reload

                expect(pending_enrollment.profile.in_person_verification_pending_at).to be_nil
                expect(pending_enrollment.profile.active).to be false
                expect(pending_enrollment.profile.deactivation_reason).
                  to eq('verification_cancelled')
              end
            end

            context 'when a unique id is invalid' do
              # this unique id is hardcoded into the fixture
              # request_unexpected_invalid_applicant_response.json
              let(:pending_enrollments) do
                [
                  create(:in_person_enrollment, :pending, unique_id: '123456789abcdefghi'),
                ]
              end
              before(:each) do
                stub_request_unexpected_invalid_applicant
              end

              it 'cancels the enrollment and logs that it was invalid' do
                job.perform(Time.zone.now)

                expect(pending_enrollment.reload.cancelled?).to be_truthy
                expect(job_analytics).to have_logged_event(
                  'GetUspsProofingResultsJob: Unexpected response received',
                  hash_including(
                    reason: 'Invalid applicant unique id',
                    response_message: /Applicant [0-9a-z]{18} does not exist/,
                    job_name: 'GetUspsProofingResultsJob',
                  ),
                )
              end
            end
          end

          context 'when USPS returns a non-hash response' do
            before(:each) do
              stub_request_proofing_results_with_responses({})
            end

            it_behaves_like(
              'enrollment_encountering_an_exception',
              reason: 'Bad response structure',
            )
          end

          context 'when USPS returns an unexpected status' do
            before(:each) do
              stub_request_passed_proofing_unsupported_status_results
            end

            it_behaves_like(
              'enrollment_encountering_an_exception',
              reason: 'Unsupported status',
            )

            it 'logs the status received' do
              job.perform(Time.zone.now)
              pending_enrollment.reload

              expect(pending_enrollment.pending?).to be_truthy
              expect(job_analytics).to have_logged_event(
                'GetUspsProofingResultsJob: Exception raised',
                hash_including(
                  status: 'Not supported',
                  job_name: 'GetUspsProofingResultsJob',
                ),
              )
            end
          end

          context 'when USPS returns invalid JSON' do
            before(:each) do
              stub_request_proofing_results_with_invalid_response
            end

            it_behaves_like(
              'enrollment_encountering_an_exception',
              reason: 'Bad response structure',
            )
          end

          context 'when USPS returns an unexpected 400 status code' do
            before(:each) do
              stub_request_proofing_results_with_responses(
                {
                  status: 400,
                  body: { 'responseMessage' => 'This USPS location has closed 😭' }.to_json,
                  headers: { 'content-type': 'application/json' },
                },
              )
            end

            it_behaves_like(
              'enrollment_encountering_an_exception',
              exception_class: 'Faraday::BadRequestError',
              exception_message: 'the server responded with status 400',
              response_message: 'This USPS location has closed 😭',
              response_status_code: 400,
            )

            it 'logs the error to NewRelic' do
              expect(NewRelic::Agent).to receive(:notice_error).
                with(instance_of(Faraday::BadRequestError)).at_least(1).times
              job.perform(Time.zone.now)
            end
          end

          context 'when USPS returns a >400 status code' do
            before(:each) do
              stub_request_proofing_results_with_responses(
                {
                  status: 410,
                  body: { 'responseMessage' => 'Applicant does not exist' }.to_json,
                  headers: { 'content-type': 'application/json' },
                },
              )
            end

            it_behaves_like(
              'enrollment_encountering_an_exception',
              exception_class: 'Faraday::ClientError',
              exception_message: 'the server responded with status 410',
              response_message: 'Applicant does not exist',
              response_status_code: 410,
            )

            it 'logs the error to NewRelic' do
              expect(NewRelic::Agent).to receive(:notice_error).
                with(instance_of(Faraday::ClientError)).at_least(1).times
              job.perform(Time.zone.now)
            end
          end

          context 'when USPS returns a 5xx status code' do
            before(:each) do
              stub_request_proofing_results_internal_server_error
            end

            it_behaves_like(
              'enrollment_encountering_an_exception',
              exception_class: 'Faraday::ServerError',
              exception_message: 'the server responded with status 500',
              response_message: 'An internal error occurred processing the request',
              response_status_code: 500,
            )

            it 'logs the error to NewRelic' do
              expect(NewRelic::Agent).to receive(:notice_error).
                with(instance_of(Faraday::ServerError)).at_least(1).times
              job.perform(Time.zone.now)
            end
          end

          context 'when there is no status update' do
            before(:each) do
              stub_request_in_progress_proofing_results
            end

            it 'updates the timestamp but does not update the status or log a message' do
              freeze_time do
                pending_enrollment.update(
                  enrollment_established_at: Time.zone.now - 3.days,
                  status_check_attempted_at: Time.zone.now - 1.day,
                  status_updated_at: Time.zone.now - 1.day,
                )

                job.perform(Time.zone.now)

                pending_enrollment.reload
                expect(pending_enrollment.enrollment_established_at).to eq(Time.zone.now - 3.days)
                expect(pending_enrollment.status_updated_at).to eq(Time.zone.now - 1.day)
                expect(pending_enrollment.status_check_attempted_at).to eq(Time.zone.now)
                expect(pending_enrollment.status_check_completed_at).to eq(Time.zone.now)
              end

              expect(pending_enrollment.profile.active).to eq(false)
              expect(pending_enrollment.pending?).to be_truthy

              expect(job_analytics).not_to have_logged_event(
                'GetUspsProofingResultsJob: Enrollment status updated',
              )

              expect(job_analytics).to have_logged_event(
                'GetUspsProofingResultsJob: Enrollment incomplete',
                hash_including(
                  response_message: 'Customer has not been to a post office to complete IPP',
                  job_name: 'GetUspsProofingResultsJob',
                ),
              )
            end
          end

          context 'when a timeout error occurs' do
            before(:each) do
              stub_request_proofing_results_with_timeout_error
            end

            it_behaves_like(
              'enrollment_encountering_an_error_that_has_a_nil_response',
              error_type: Faraday::TimeoutError,
            )
          end

          context 'when a connection failed error occurs' do
            before(:each) do
              stub_request_proofing_results_with_connection_failed_error
            end

            it_behaves_like(
              'enrollment_encountering_an_error_that_has_a_nil_response',
              error_type: Faraday::ConnectionFailed,
            )
          end

          context 'when a nil status error occurs' do
            before(:each) do
              stub_request_proofing_results_with_nil_status_error
            end

            it_behaves_like(
              'enrollment_encountering_an_error_that_has_a_nil_response',
              error_type: Faraday::NilStatusError,
            )
          end

          context 'when a user was flagged with fraud_pending_reason' do
            before(:each) do
              pending_enrollment.profile.update!(fraud_pending_reason: 'threatmetrix_review')
              stub_request_passed_proofing_results
            end

            it 'updates the enrollment' do
              freeze_time do
                expect(pending_enrollment.status).to eq 'pending'
                job.perform(Time.zone.now)
                expect(pending_enrollment.reload.status).to eq 'passed'
              end
            end

            context 'when the in_person_proofing_enforce_tmx flag is false' do
              before do
                allow(IdentityConfig.store).to receive(:in_person_proofing_enforce_tmx).
                  and_return(false)
              end

              it 'activates the profile' do
                job.perform(Time.zone.now)
                profile = pending_enrollment.reload.profile
                expect(profile).to be_active
              end

              it 'does not mark the user as fraud_review_pending_at' do
                job.perform(Time.zone.now)

                profile = pending_enrollment.reload.profile
                expect(profile).not_to be_fraud_review_pending
              end

              it 'does not log a user_sent_to_fraud_review analytics event' do
                job.perform(Time.zone.now)

                expect(job_analytics).not_to have_logged_event(
                  :idv_in_person_usps_proofing_results_job_user_sent_to_fraud_review,
                )
              end

              it 'does not set the fraud related fields of an expired enrollment' do
                stub_request_expired_id_ipp_proofing_results

                job.perform(Time.zone.now)
                profile = pending_enrollment.reload.profile

                expect(profile.fraud_review_pending_at).to be_nil
                expect(profile.fraud_rejection_at).to be_nil
                expect(job_analytics).not_to have_logged_event(
                  :idv_ipp_deactivated_for_never_visiting_post_office,
                )
              end
            end

            context 'when the in_person_proofing_enforce_tmx flag is true' do
              before do
                allow(IdentityConfig.store).to receive(:in_person_proofing_enforce_tmx).
                  and_return(true)
              end

              it 'preserves the fraud_pending_reason attribute' do
                job.perform(Time.zone.now)

                expect(pending_enrollment.profile.fraud_pending_reason).to eq 'threatmetrix_review'
              end

              it 'logs a user_sent_to_fraud_review analytics event' do
                job.perform(Time.zone.now)

                expect(job_analytics).to have_logged_event(
                  :idv_in_person_usps_proofing_results_job_user_sent_to_fraud_review,
                  hash_including(
                    enrollment_code: pending_enrollment.enrollment_code,
                  ),
                )
              end

              it 'does not send a success email' do
                user = pending_enrollment.user

                freeze_time do
                  expect do
                    job.perform(Time.zone.now)
                  end.not_to have_enqueued_mail(UserMailer, :in_person_verified).with(
                    params: { user: user, email_address: user.email_addresses.first },
                    args: [{ enrollment: pending_enrollment }],
                  )
                end
              end

              it 'marks the user as fraud_review_pending_at' do
                job.perform(Time.zone.now)

                profile = pending_enrollment.reload.profile
                expect(profile.fraud_review_pending_at).not_to be_nil
                expect(profile).not_to be_active
              end

              context 'when the enrollment has passed' do
                before(:each) do
                  pending_enrollment.profile.update!(fraud_pending_reason: 'threatmetrix_review')
                  stub_request_passed_proofing_results
                end

                it 'sends the please call email' do
                  user = pending_enrollment.user

                  freeze_time do
                    expect do
                      job.perform(Time.zone.now)
                    end.to have_enqueued_mail(UserMailer, :in_person_please_call).with(
                      params: { user: user, email_address: user.email_addresses.first },
                      args: [{ enrollment: pending_enrollment }],
                    )
                  end
                end

                it 'logs the expected analytics events' do
                  freeze_time do
                    job.perform(Time.zone.now)
                  end
                  expect(job_analytics).to have_logged_event(
                    :idv_in_person_usps_proofing_results_job_please_call_email_initiated,
                    hash_including(
                      job_name: 'GetUspsProofingResultsJob',
                    ),
                  )
                  expect(job_analytics).to have_logged_event(
                    'GetUspsProofingResultsJob: Enrollment status updated',
                    hash_including(
                      passed: true,
                      reason: 'Passed with fraud pending',
                      job_name: 'GetUspsProofingResultsJob',
                      enhanced_ipp: false,
                    ),
                  )
                end
              end

              context 'when the enrollment has failed' do
                before do
                  stub_request_failed_proofing_results
                end

                it 'sends proofing failed email on response with failed status' do
                  user = pending_enrollment.user

                  freeze_time do
                    expect do
                      job.perform(Time.zone.now)
                    end.to have_enqueued_mail(UserMailer, :in_person_failed).with(
                      params: { user: user, email_address: user.email_addresses.first },
                      args: [{ enrollment: pending_enrollment }],
                    )
                    expect(job_analytics).to have_logged_event(
                      'GetUspsProofingResultsJob: Success or failure email initiated',
                      hash_including(
                        email_type: 'Failed',
                        job_name: 'GetUspsProofingResultsJob',
                      ),
                    )
                  end
                end

                it 'deactivates the associated profile' do
                  expect(pending_enrollment.profile.in_person_verification_pending_at).not_to be_nil

                  job.perform(Time.zone.now)
                  pending_enrollment.reload
                  expect(pending_enrollment.profile.in_person_verification_pending_at).to be_nil
                  expect(pending_enrollment.profile.active).to be false
                  expect(pending_enrollment.profile.deactivation_reason).
                    to eq('verification_cancelled')
                end

                it 'deactivates and sets fraud related fields of an expired enrollment' do
                  stub_request_expired_id_ipp_proofing_results

                  job.perform(Time.zone.now)

                  profile = pending_enrollment.reload.profile
                  expect(profile).not_to be_active
                  expect(profile.fraud_review_pending_at).to be_nil
                  expect(profile.fraud_rejection_at).not_to be_nil
                  expect(job_analytics).to have_logged_event(
                    :idv_ipp_deactivated_for_never_visiting_post_office,
                  )
                end
              end
            end
          end
        end

        describe 'Proofed with secondary id' do
          let!(:pending_enrollments) do
            ['BALTIMORE', 'FRIENDSHIP', 'WASHINGTON', 'ARLINGTON', 'DEANWOOD'].map do |name|
              create(
                :in_person_enrollment,
                :pending,
                :with_notification_phone_configuration,
                issuer: 'http://localhost:3000',
                selected_location_details: { name: name },
                sponsor_id: usps_ipp_sponsor_id,
              )
            end
          end
          let(:pending_enrollment) { pending_enrollments.first }

          before do
            enrollment_records = InPersonEnrollment.where(id: pending_enrollments.map(&:id))
            allow(InPersonEnrollment).to receive(:needs_usps_status_check).
              and_return(enrollment_records)
            allow(IdentityConfig.store).to receive(:in_person_proofing_enabled).and_return(true)
          end

          before do
            allow(IdentityConfig.store).to receive(:in_person_proofing_enabled).and_return(true)
          end

          context 'when an enrollment passes proofing with a secondary ID' do
            before do
              stub_request_passed_proofing_secondary_id_type_results
            end

            it_behaves_like(
              'enrollment_with_a_status_update',
              passed: false,
              email_type: 'Failed unsupported secondary ID',
              enrollment_status: InPersonEnrollment::STATUS_FAILED,
              response_json: UspsInPersonProofing::Mock::Fixtures.
                request_passed_proofing_secondary_id_type_results_response,
            )

            it 'deactivates the associated profile' do
              expect(pending_enrollment.profile.in_person_verification_pending_at).not_to be_nil
              job.perform(Time.zone.now)
              pending_enrollment.reload

              expect(pending_enrollment.profile.in_person_verification_pending_at).to be_nil
              expect(pending_enrollment.profile.active).to be false
              expect(pending_enrollment.profile.deactivation_reason).to eq('verification_cancelled')
            end

            it 'logs a message about enrollment with secondary ID' do
              allow(IdentityConfig.store).to receive(
                :in_person_send_proofing_notifications_enabled,
              ).and_return(true)
              freeze_time do
                expect do
                  job.perform Time.zone.now
                  pending_enrollment.reload
                end.to have_enqueued_job(InPerson::SendProofingNotificationJob).
                  with(pending_enrollment.id).at(1.hour.from_now).on_queue(:intentionally_delayed)
              end

              expect(pending_enrollment.proofed_at).to eq(transaction_end_date_time)
              expect(pending_enrollment.profile.active).to eq(false)
              expect(job_analytics).to have_logged_event(
                'GetUspsProofingResultsJob: Enrollment status updated',
                hash_including(
                  passed: false,
                  reason: 'Provided secondary proof of address',
                  job_name: 'GetUspsProofingResultsJob',
                  enhanced_ipp: false,
                ),
              )
            end

            context 'when the secondary ID is supported' do
              before do
                stub_request_passed_proofing_supported_secondary_id_type_results
              end

              it_behaves_like(
                'enrollment_with_a_status_update',
                passed: true,
                email_type: 'Success',
                enrollment_status: InPersonEnrollment::STATUS_PASSED,
                response_json: UspsInPersonProofing::Mock::Fixtures.
                  request_passed_proofing_supported_secondary_id_type_results_response,
              )
            end
          end
        end

        describe 'sms notifications enabled' do
          let(:pending_enrollment) do
            create(
              :in_person_enrollment, :pending, :with_notification_phone_configuration
            )
          end
          before do
            allow(IdentityConfig.store).to receive(:in_person_proofing_enabled).and_return(true)
            allow(IdentityConfig.store).to receive(:in_person_send_proofing_notifications_enabled).
              and_return(true)
          end

          context 'enrollment is expired' do
            it 'deletes the notification phone configuration without sending an sms' do
              stub_request_expired_id_ipp_proofing_results

              expect(pending_enrollment.notification_phone_configuration).to_not be_nil

              job.perform(Time.zone.now)

              expect(pending_enrollment.reload.notification_phone_configuration).to be_nil
              expect(pending_enrollment.notification_sent_at).to be_nil
            end
          end

          context 'enrollment has passed proofing' do
            it 'invokes the SendProofingNotificationJob for the enrollment' do
              stub_request_passed_proofing_results

              expect(pending_enrollment.notification_phone_configuration).to_not be_nil
              expect(pending_enrollment.notification_sent_at).to be_nil

              expect { job.perform(Time.zone.now) }.
                to have_enqueued_job(InPerson::SendProofingNotificationJob).
                with(pending_enrollment.id)
            end
          end

          context 'enrollment has failed proofing' do
            it 'invokes the SendProofingNotificationJob for the enrollment' do
              stub_request_failed_proofing_results

              expect(pending_enrollment.notification_phone_configuration).to_not be_nil
              expect(pending_enrollment.notification_sent_at).to be_nil

              expect { job.perform(Time.zone.now) }.
                to have_enqueued_job(InPerson::SendProofingNotificationJob).
                with(pending_enrollment.id)
            end
          end

          context 'enrollment has failed proofing due to unsupported secondary ID' do
            it 'invokes the SendProofingNotificationJob for the enrollment' do
              stub_request_passed_proofing_secondary_id_type_results

              expect(pending_enrollment.notification_phone_configuration).to_not be_nil
              expect(pending_enrollment.notification_sent_at).to be_nil

              expect { job.perform(Time.zone.now) }.
                to have_enqueued_job(InPerson::SendProofingNotificationJob).
                with(pending_enrollment.id)
            end
          end

          context 'enrollment has failed proofing due to unsupported ID type' do
            it 'invokes the SendProofingNotificationJob for the enrollment' do
              stub_request_passed_proofing_unsupported_id_results

              expect(pending_enrollment.notification_phone_configuration).to_not be_nil
              expect(pending_enrollment.notification_sent_at).to be_nil

              expect { job.perform(Time.zone.now) }.
                to have_enqueued_job(InPerson::SendProofingNotificationJob).
                with(pending_enrollment.id)
            end
          end
        end
      end

      describe 'Enhanced In-Person Proofing' do
        let!(:pending_enrollment) do
          create(
            :in_person_enrollment,
            :pending,
            :with_notification_phone_configuration,
            issuer: 'http://localhost:3000',
            selected_location_details: { name: 'BALTIMORE' },
            sponsor_id: usps_eipp_sponsor_id,
          )
        end

        before do
          allow(IdentityConfig.store).to receive(:in_person_proofing_enabled).and_return(true)
        end

        context <<~STR.squish do
          When an Enhanced IPP enrollment passes proofing
          with unsupported ID,enrollment by-passes the
          Primary ID check and
        STR

          before do
            stub_request_passed_proofing_unsupported_id_results
          end

          it_behaves_like(
            'enrollment_with_a_status_update',
            passed: true,
            email_type: 'Success',
            enrollment_status: InPersonEnrollment::STATUS_PASSED,
            response_json: UspsInPersonProofing::Mock::Fixtures.
              request_passed_proofing_unsupported_id_results_response,
            enhanced_ipp_enrollment: true,
          )

          it 'invokes the SendProofingNotificationJob and logs details about the success' do
            allow(IdentityConfig.store).to receive(:in_person_send_proofing_notifications_enabled).
              and_return(true)
            expected_wait_until = nil
            freeze_time do
              expected_wait_until = 1.hour.from_now
              expect do
                job.perform(Time.zone.now)
                pending_enrollment.reload
              end.to have_enqueued_job(InPerson::SendProofingNotificationJob).
                with(pending_enrollment.id).at(expected_wait_until).on_queue(:intentionally_delayed)
            end

            expect(pending_enrollment.proofed_at).to eq(transaction_end_date_time)
            expect(job_analytics).to have_logged_event(
              'GetUspsProofingResultsJob: Enrollment status updated',
              hash_including(
                reason: 'Successful status update',
                passed: true,
                job_name: 'GetUspsProofingResultsJob',
                enhanced_ipp: true,
              ),
            )
            expect(job_analytics).to have_logged_event(
              'GetUspsProofingResultsJob: Success or failure email initiated',
              email_type: 'Success',
              enrollment_code: pending_enrollment.enrollment_code,
              service_provider: anything,
              timestamp: anything,
              wait_until: expected_wait_until,
              job_name: 'GetUspsProofingResultsJob',
            )
          end
        end

        context 'Bypasses the Secondary ID check when enrollment is Enhanced IPP' do
          before do
            stub_request_passed_proofing_secondary_id_type_results_ial_2
          end

          it_behaves_like(
            'enrollment_with_a_status_update',
            passed: true,
            email_type: 'Success',
            enrollment_status: InPersonEnrollment::STATUS_PASSED,
            response_json: UspsInPersonProofing::Mock::Fixtures.
            request_passed_proofing_secondary_id_type_results_response_ial_2,
            enhanced_ipp_enrollment: true,
          )
        end

        context 'when an enrollment expires' do
          before(:each) do
            stub_request_expired_enhanced_ipp_proofing_results
          end

          it_behaves_like(
            'enrollment_with_a_status_update',
            passed: false,
            email_type: 'deadline passed',
            enrollment_status: InPersonEnrollment::STATUS_EXPIRED,
            response_json: UspsInPersonProofing::Mock::Fixtures.
            request_expired_enhanced_ipp_results_response,
            enhanced_ipp_enrollment: true,
          )

          it 'logs that the enrollment expired' do
            job.perform(Time.zone.now)

            expect(pending_enrollment.proofed_at).to eq(nil)
            expect(job_analytics).to have_logged_event(
              'GetUspsProofingResultsJob: Enrollment status updated',
              hash_including(
                reason: 'Enrollment has expired',
                job_name: 'GetUspsProofingResultsJob',
                enhanced_ipp: true,
              ),
            )
          end

          context 'when the in_person_stop_expiring_enrollments flag is true' do
            before do
              allow(IdentityConfig.store).to(
                receive(:in_person_stop_expiring_enrollments).and_return(true),
              )
            end

            it 'treats the enrollment as incomplete' do
              job.perform(Time.zone.now)

              expect(pending_enrollment.status).to eq(InPersonEnrollment::STATUS_PENDING)
              expect(job_analytics).to have_logged_event(
                'GetUspsProofingResultsJob: Enrollment incomplete',
                hash_including(
                  response_message: 'More than 7 days have passed since opt-in to IPP',
                  job_name: 'GetUspsProofingResultsJob',
                ),
              )
            end
          end
        end
      end
    end

    describe 'IPP disabled' do
      before do
        allow(IdentityConfig.store).to receive(:in_person_proofing_enabled).and_return(false)
        allow(IdentityConfig.store).to receive(:usps_mock_fallback).and_return(false)
      end

      it 'does not request any enrollment records' do
        # no stubbing means this test will fail if the UspsInPersonProofing::Proofer
        # tries to connect to the USPS API
        job.perform Time.zone.now
      end
    end

    describe 'IPP Enrollments Ready Job Enabled' do
      before do
        allow(IdentityConfig.store).to(
          receive(:in_person_enrollments_ready_job_enabled).and_return(true),
        )
        allow(IdentityConfig.store).to receive(:usps_mock_fallback).and_return(false)
      end

      it 'does not request any enrollment records' do
        # no stubbing means this test will fail if the UspsInPersonProofing::Proofer
        # tries to connect to the USPS API
        job.perform Time.zone.now
      end
    end
  end
end
