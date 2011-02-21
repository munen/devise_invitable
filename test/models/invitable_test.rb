require 'test/test_helper'
require 'test/model_tests_helper'

class InvitableTest < ActiveSupport::TestCase

  def setup
    setup_mailer
  end

  test 'should not generate invitation token after creating a record' do
    assert_nil new_user.invitation_token
  end

  test 'should not regenerate invitation token each time' do
    user = new_user
    user.invite!
    token = user.invitation_token
    assert_not_nil user.invitation_token
    assert_not_nil user.invitation_sent_at
    3.times do
      user.invite!
      assert_equal token, user.invitation_token
    end
  end

  test 'should set invitation sent at each time' do
    user = new_user
    user.invite!
    old_invitation_sent_at = 3.days.ago
    user.update_attributes(:invitation_sent_at => old_invitation_sent_at)
    3.times do
      user.invite!
      assert_not_equal old_invitation_sent_at, user.invitation_sent_at
      user.update_attributes(:invitation_sent_at => old_invitation_sent_at)
    end
  end

  test 'should not regenerate invitation token even after the invitation token is not valid' do
    User.stubs(:invite_for).returns(1.day)
    user = new_user
    user.invite!
    token = user.invitation_token
    user.invitation_sent_at = 3.days.ago
    user.save
    user.invite!
    assert_equal token, user.invitation_token
  end

  test 'should test invitation sent at with invite_for configuration value' do
    user = User.invite!(:email => "valid@email.com")
    
    User.stubs(:invite_for).returns(nil)
    user.invitation_sent_at = Time.now.utc
    assert user.valid_invitation?

    User.stubs(:invite_for).returns(nil)
    user.invitation_sent_at = 1.year.ago
    assert user.valid_invitation?

    User.stubs(:invite_for).returns(0)
    user.invitation_sent_at = Time.now.utc
    assert user.valid_invitation?

    User.stubs(:invite_for).returns(0)
    user.invitation_sent_at = 1.day.ago
    assert user.valid_invitation?

    User.stubs(:invite_for).returns(1.day)
    user.invitation_sent_at = Time.now.utc
    assert user.valid_invitation?

    User.stubs(:invite_for).returns(1.day)
    user.invitation_sent_at = 1.day.ago
    assert !user.valid_invitation?
  end

  test 'should never generate the same invitation token for different users' do
    invitation_tokens = []
    3.times do
      user = new_user
      user.invite!
      token = user.invitation_token
      assert !invitation_tokens.include?(token)
      invitation_tokens << token
    end
  end

  test 'should disallow login when invited' do
    invited_user = User.invite!(:email => "valid@email.com")
    assert !invited_user.valid_password?('1234')
  end

  test 'should set password and password confirmation from params' do
    invited_user = User.invite!(:email => "valid@email.com")
    user = User.accept_invitation!(:invitation_token => invited_user.invitation_token, :password => '123456789', :password_confirmation => '123456789')
    assert user.valid_password?('123456789')
  end

  test 'should set password and save the record' do
    user = User.invite!(:email => "valid@email.com")
    old_encrypted_password = user.encrypted_password
    user = User.accept_invitation!(:invitation_token => user.invitation_token, :password => '123456789', :password_confirmation => '123456789')
    assert_not_equal old_encrypted_password, user.encrypted_password
  end

  test 'should clear invitation token while accepting the password' do
    user = User.invite!(:email => "valid@email.com")
    assert_present user.invitation_token
    user.accept_invitation!
    assert_nil user.reload.invitation_token
  end

  test 'should not clear invitation token if record is invalid' do
    user = User.invite!(:email => "valid@email.com")
    assert_present user.invitation_token
    User.accept_invitation!(:invitation_token => user.invitation_token, :password => '123456789', :password_confirmation => '987654321')
    user.reload
    assert_present user.invitation_token
  end

  test 'should clear invitation token while resetting the password' do
    user = User.invite!(:email => "valid@email.com")
    user.send(:generate_reset_password_token!)
    assert_present user.reset_password_token
    assert_present user.invitation_token
    User.reset_password_by_token(:reset_password_token => user.reset_password_token, :password => '123456789', :password_confirmation => '123456789')
    assert_nil user.reload.invitation_token
  end

  test 'should reset invitation token and send invitation by email' do
    user = new_user
    assert_difference('ActionMailer::Base.deliveries.size') do
      token = user.invitation_token
      user.invite!
      assert_not_equal token, user.invitation_token
    end
  end

  test 'should return a record with invitation token and no errors to send invitation by email' do
    invited_user = User.invite!(:email => "valid@email.com")
    assert invited_user.errors.blank?
    assert_present invited_user.invitation_token
    assert_equal 'valid@email.com', invited_user.email
    assert invited_user.persisted?
  end

  test 'should set all attributes with no errors' do
    invited_user = User.invite!(:email => "valid@email.com", :username => 'first name')
    assert invited_user.errors.blank?
    assert_equal 'first name', invited_user.username
    assert invited_user.persisted?
  end

  test 'should return a record with errors if user was found by e-mail' do
    existing_user = User.new(:email => "valid@email.com")
    existing_user.save(:validate => false)
    user = User.invite!(:email => "valid@email.com")
    # puts existing_user.inspect
    # puts user.inspect
    assert_equal user, existing_user
    assert_equal ['has already been taken'], user.errors[:email]
  end

  test 'should return a new record with errors if e-mail is blank' do
    invited_user = User.invite!(:email => '')
    assert invited_user.new_record?
    assert_equal ["can't be blank"], invited_user.errors[:email]
  end

  test 'should return a new record with errors if e-mail is invalid' do
    invited_user = User.invite!(:email => 'invalid_email')
    assert invited_user.new_record?
    assert_equal ["is invalid"], invited_user.errors[:email]
  end

  test 'should set all attributes with errors if e-mail is invalid' do
    invited_user = User.invite!(:email => "invalid_email.com", :username => 'first name')
    assert invited_user.new_record?
    assert_equal 'first name', invited_user.username
    assert invited_user.errors.present?
  end

  test 'should find a user to set his password based on invitation_token' do
    user = new_user
    user.invite!
    invited_user = User.accept_invitation!(:invitation_token => user.invitation_token)
    assert_equal invited_user, user
  end

  test 'should return a new record with errors if no invitation_token is found' do
    invited_user = User.accept_invitation!(:invitation_token => 'invalid_token')
    assert invited_user.new_record?
    assert_equal ['is invalid'], invited_user.errors[:invitation_token]
  end

  test 'should return a new record with errors if invitation_token is blank' do
    invited_user = User.accept_invitation!(:invitation_token => '')
    assert invited_user.new_record?
    assert_equal ["can't be blank"], invited_user.errors[:invitation_token]
  end

  test 'should return record with errors if invitation_token has expired' do
    User.stubs(:invite_for).returns(10.hours)
    invited_user = User.invite!(:email => "valid@email.com")
    invited_user.invitation_sent_at = 2.days.ago
    invited_user.save(:validate => false)
    user = User.accept_invitation!(:invitation_token => invited_user.invitation_token)
    assert_equal user, invited_user
    assert_equal ["is invalid"], user.errors[:invitation_token]
  end

  test 'should set successfully user password given the new password and confirmation' do
    user = new_user(:password => nil, :password_confirmation => nil)
    user.invite!

    invited_user = User.accept_invitation!(
      :invitation_token => user.invitation_token,
      :password => 'new_password',
      :password_confirmation => 'new_password'
    )
    user.reload

    assert user.valid_password?('new_password')
  end

  test 'user.has_invitations_left? test' do
    # By default with invitation_limit nil, users can send unlimited invitations
    user = new_user
    assert_nil user.invitation_limit
    assert user.has_invitations_left?

    # With invitation_limit set to a value, all users can send that many invitations
    User.stubs(:invitation_limit).returns(2)
    assert user.has_invitations_left?

    # With an individual invitation_limit of 0, a user shouldn't be able to send an invitation
    user.invitation_limit = 0
    assert user.save
    assert !user.has_invitations_left?

    # With in invitation_limit of 2, a user should be able to send two invitations
    user.invitation_limit = 2
    assert user.save
    assert user.has_invitations_left?
  end

end
