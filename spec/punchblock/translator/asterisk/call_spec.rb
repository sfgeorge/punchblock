require 'spec_helper'

module Punchblock
  module Translator
    class Asterisk
      describe Call do
        let(:channel)         { 'SIP/foo' }
        let(:translator)      { stub_everything 'Translator::Asterisk' }
        let(:env)             { "agi_request%3A%20async%0Aagi_channel%3A%20SIP%2F1234-00000000%0Aagi_language%3A%20en%0Aagi_type%3A%20SIP%0Aagi_uniqueid%3A%201320835995.0%0Aagi_version%3A%201.8.4.1%0Aagi_callerid%3A%205678%0Aagi_calleridname%3A%20Jane%20Smith%0Aagi_callingpres%3A%200%0Aagi_callingani2%3A%200%0Aagi_callington%3A%200%0Aagi_callingtns%3A%200%0Aagi_dnid%3A%201000%0Aagi_rdnis%3A%20unknown%0Aagi_context%3A%20default%0Aagi_extension%3A%201000%0Aagi_priority%3A%201%0Aagi_enhanced%3A%200.0%0Aagi_accountcode%3A%20%0Aagi_threadid%3A%204366221312%0A%0A" }
        let(:agi_env) do
          {
            :agi_request      => 'async',
            :agi_channel      => 'SIP/1234-00000000',
            :agi_language     => 'en',
            :agi_type         => 'SIP',
            :agi_uniqueid     => '1320835995.0',
            :agi_version      => '1.8.4.1',
            :agi_callerid     => '5678',
            :agi_calleridname => 'Jane Smith',
            :agi_callingpres  => '0',
            :agi_callingani2  => '0',
            :agi_callington   => '0',
            :agi_callingtns   => '0',
            :agi_dnid         => '1000',
            :agi_rdnis        => 'unknown',
            :agi_context      => 'default',
            :agi_extension    => '1000',
            :agi_priority     => '1',
            :agi_enhanced     => '0.0',
            :agi_accountcode  => '',
            :agi_threadid     => '4366221312'
          }
        end

        let :sip_headers do
          {
            :x_agi_request      => 'async',
            :x_agi_channel      => 'SIP/1234-00000000',
            :x_agi_language     => 'en',
            :x_agi_type         => 'SIP',
            :x_agi_uniqueid     => '1320835995.0',
            :x_agi_version      => '1.8.4.1',
            :x_agi_callerid     => '5678',
            :x_agi_calleridname => 'Jane Smith',
            :x_agi_callingpres  => '0',
            :x_agi_callingani2  => '0',
            :x_agi_callington   => '0',
            :x_agi_callingtns   => '0',
            :x_agi_dnid         => '1000',
            :x_agi_rdnis        => 'unknown',
            :x_agi_context      => 'default',
            :x_agi_extension    => '1000',
            :x_agi_priority     => '1',
            :x_agi_enhanced     => '0.0',
            :x_agi_accountcode  => '',
            :x_agi_threadid     => '4366221312'
          }
        end

        subject { Call.new channel, translator, env }

        its(:id)          { should be_a String }
        its(:channel)     { should == channel }
        its(:translator)  { should be translator }
        its(:agi_env)     { should == agi_env }

        describe '#register_component' do
          it 'should make the component accessible by ID' do
            component_id = 'abc123'
            component    = mock 'Translator::Asterisk::Component', :id => component_id
            subject.register_component component
            subject.component_with_id(component_id).should be component
          end
        end

        describe '#send_offer' do
          it 'sends an offer to the translator' do
            expected_offer = Punchblock::Event::Offer.new :call_id  => subject.id,
                                                          :to       => '1000',
                                                          :from     => 'sip:5678',
                                                          :headers  => sip_headers
            translator.expects(:handle_pb_event!).with expected_offer
            subject.send_offer
          end
        end

        describe '#process_ami_event' do
          context 'with a Hangup event' do
            let :ami_event do
              RubyAMI::Event.new('Hangup').tap do |e|
                e['Uniqueid']     = "1320842458.8"
                e['Calleridnum']  = "5678"
                e['Calleridname'] = "Jane Smith"
                e['Cause']        = "0"
                e['Cause-txt']    = "Unknown"
                e['Channel']      = "SIP/1234-00000000"
              end
            end

            it 'should send an end event to the translator' do
              expected_end_event = Punchblock::Event::End.new :reason   => :hangup,
                                                              :call_id  => subject.id
              translator.expects(:handle_pb_event!).with expected_end_event
              subject.process_ami_event ami_event
            end
          end
        end

        describe '#execute_command' do
          context 'with an accept command' do
            let(:command) { Command::Accept.new }

            before do
              command.request!
            end

            it "should send an EXEC RINGING AGI command and set the command's response" do
              subject.execute_command command
              ami_action = subject.actor_subject.instance_variable_get(:'@current_ami_action')
              ami_action.name.should == "agi"
              ami_action.headers['Command'].should == "EXEC RINGING"
              ami_action << RubyAMI::Response.new
              command.response(0.5).should be true
            end
          end

          context 'with an answer command' do
            let(:command) { Command::Answer.new }

            before do
              command.request!
            end

            it "should send an EXEC ANSWER AGI command and set the command's response" do
              subject.execute_command command
              ami_action = subject.actor_subject.instance_variable_get(:'@current_ami_action')
              ami_action.name.should == "agi"
              ami_action.headers['Command'].should == "EXEC ANSWER"
              ami_action << RubyAMI::Response.new
              command.response(0.5).should be true
            end
          end

          context 'with a hangup command' do
            let(:command) { Command::Hangup.new }

            before do
              command.request!
            end

            it "should send a Hangup AMI command and set the command's response" do
              subject.execute_command command
              ami_action = subject.actor_subject.instance_variable_get(:'@current_ami_action')
              ami_action.name.should == "hangup"
              ami_action << RubyAMI::Response.new
              command.response(0.5).should be true
            end
          end
        end

        describe '#send_agi_action' do
          it 'should send an appropriate AsyncAGI AMI action' do
            subject.actor_subject.expects(:send_ami_action).once.with('AGI', 'Command' => 'FOO', 'Channel' => subject.channel)
            subject.send_agi_action 'FOO'
          end
        end

        describe '#send_ami_action' do
          let(:component_id) { UUIDTools::UUID.random_create }
          before { UUIDTools::UUID.stubs :random_create => component_id }

          it 'should send the action to the AMI client' do
            action = RubyAMI::Action.new 'foo', :foo => :bar
            translator.expects(:send_ami_action!).once.with action
            subject.send_ami_action 'foo', :foo => :bar
          end
        end
      end
    end
  end
end
