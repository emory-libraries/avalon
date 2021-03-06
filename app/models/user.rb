# Copyright 2011-2020, The Trustees of Indiana University and Northwestern
#   University.  Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software distributed
#   under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
#   CONDITIONS OF ANY KIND, either express or implied. See the License for the
#   specific language governing permissions and limitations under the License.
# ---  END LICENSE_HEADER BLOCK  ---

class User < ActiveRecord::Base
  attr_writer :login
  # Connects this user object to Hydra behaviors.
  include Hydra::User

  # if Blacklight::Utils.needs_attr_accessible?
  #   attr_accessible :email, :password, :password_confirmation
  # end
  # Connects this user object to Blacklights Bookmarks.
  include Blacklight::User

  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable
  # Registration is controlled via settings.yml
  devise_list = [:omniauthable, :rememberable, :trackable, omniauth_providers: [:saml], authentication_keys: [:login]]
  devise_list.prepend(:database_authenticatable) if AuthConfig.use_database_auth?

  devise(*devise_list)

  validates :username, presence: true, uniqueness: { scope: :provider, case_sensitive: false }
  validates :email, presence: true, uniqueness: { scope: :provider, case_sensitive: false }
  validate :username_email_uniqueness

  before_destroy :remove_bookmarks

  def username_email_uniqueness
    errors.add(:email, :taken, value: email) if User.find_by_username(email) && User.find_by_username(email).id != id
    errors.add(:username, :taken, valud: username) if User.find_by_email(username) && User.find_by_email(username).id != id
  end

  # Method added by Blacklight; Blacklight uses #to_s on your
  # user class to get a user-displayable login/identifier for
  # the account.
  def to_s
    user_key
  end

  def login
    username || email
  end

  def remove_bookmarks
    Bookmark.where(user_id: self.id).destroy_all
  end

  def playlist_tags
    Playlist.where(user_id:id).collect(&:tags).flatten.reject(&:blank?).uniq.sort
  end

  def timeline_tags
    Timeline.where(user_id:id).collect(&:tags).flatten.reject(&:blank?).uniq.sort
  end

  def self.find_and_verify_by_username(username)
    user = User.find_by(username: username)
    if user&.deleted_at
      raise Avalon::DeletedUserId
    end
    user
  end

  def self.find_and_verify_by_email(email)
    user = User.find_by(email: email)
    if user&.deleted_at
      raise Avalon::DeletedUserId
    end
    user
  end

  def self.find_by_username_or_email(login)
    find_and_verify_by_username(login) || find_and_verify_by_email(login)
  end

  def self.create_new_user(username, email, provider)
    if provider == 'lti'
      user = create!(username: username, email: email, provider: provider)
    else
      password = Devise.friendly_token[0, 20]
      user = create!(username: username, email: email, password: password, password_confirmation: password, provider: provider)
    end
    user
  end

  def self.find_or_create_by_username_or_email(username, email, provider = 'local')
    find_and_verify_by_username(username) ||
      find_and_verify_by_email(email) ||
      create_new_user(username, email, provider)
  end

  def self.from_api_token(token)
    find_or_create_by_username_or_email(token.username, token.email)
  end

  def self.find_for_database_authentication(warden_conditions)
    conditions = warden_conditions.dup
    login = conditions.delete(:login)
    where(conditions).find_by(["lower(username) = :value OR lower(email) = :value", { value: login.strip.downcase }])
  end

  def self.find_for_generic(access_token, signed_in_resource=nil)
    username = access_token.uid
    email = access_token.info.email
    find_or_create_by_username_or_email(username, email, 'generic')
  end

  def self.find_for_identity(access_token, signed_in_resource=nil)
    username = access_token.info['email']
    # Use email for both username and email for the created user
    find_or_create_by_username_or_email(username, username, 'identity')
  end

  def self.find_for_lti(auth_hash, signed_in_resource=nil)
    if auth_hash.uid.blank?
      raise Avalon::MissingUserId
    end

    class_id = auth_hash.extra.context_id
    if Course.where(context_id: class_id).empty?
      class_name = auth_hash.extra.context_name
      Course.create :context_id => class_id, :label => auth_hash.extra.consumer.context_label, :title => class_name unless class_name.nil?
    end

    find_or_create_by_username_or_email(auth_hash.uid, auth_hash.info.email, 'lti')
  end

  def self.autocomplete(query)
    self.where("username LIKE :q OR email LIKE :q", q: "%#{query}%").collect { |user|
      { id: user.user_key, display: user.user_key }
    }
  end

  def in?(*list)
    list.flatten.include? user_key
  end

  #TODO extract the ldap stuff into a mixin?
  def ldap_groups
    User.walk_ldap_groups(User.ldap_member_of(user_key), []).sort
  end

  def self.ldap_member_of(cn)
    return [] unless defined? Avalon::GROUP_LDAP
    entry = Avalon::GROUP_LDAP.search(:base => Avalon::GROUP_LDAP_TREE, :filter => Net::LDAP::Filter.eq("cn", cn), :attributes => ["memberof"]).first
    entry.nil? ? [] : entry["memberof"].collect {|mo| mo.split(',').first.split('=').second}
  end

  def self.walk_ldap_groups(groups, seen)
    groups.each do |g|
      next if seen.include? g
      seen << g
      User.walk_ldap_groups(User.ldap_member_of(g), seen)
    end
    seen
  end

  # When a user authenticates via shibboleth, find their User object or make
  # a new one. Populate it with data we get from shibboleth.
  # @param [OmniAuth::AuthHash] auth
  def self.from_omniauth(auth)
    attrs = auth&.extra&.raw_info&.attributes # get attrs from saml response
    groups = attrs.present? ? attrs["urn:oid:1.3.6.1.4.1.5923.1.5.1.1"] : [] # get groups from attrs saml response
    refined_groups = []
    # separate only CN value from each group
    groups.each do |group|
      refined_groups << group.partition(',').first.delete("CN=")
    end
    # partition the string so that ldap_groups is now an array without ','
    ldap_groups = ENV['ADMIN_LDAP_GROUPS'].to_s.partition(',')
    ldap_groups.delete(',')
    # check if any values are same between the two groups, if yes, find or create user
    if (ldap_groups & refined_groups).any? && auth.provider.present? && auth.uid.present?
      user = find_or_create_by!(provider: auth.provider, username: auth.uid.downcase) do |u|
        u.email = auth.info.net_id + '@emory.edu' unless auth.info.net_id == 'tezprox'
      end
    else
      log_omniauth_error(auth)
      return User.new
    end
    user.assign_attributes(display_name: auth.info.first_name, ppid: auth.uid, uid: auth.info.net_id)
    # tezprox@emory.edu isn't a real email address
    user.email = auth.info.net_id + '@emory.edu' unless auth.info.net_id == 'tezprox'
    Avalon::RoleControls.add_user_role(user.username, 'administrator') unless Avalon::RoleControls.user_roles(user.username).include?('administrator')
    user.save
    user
  end

  def self.log_omniauth_error(auth)
    if auth.uid&.empty?
      Rails.logger.error "Nil user detected: Shibboleth didn't pass a uid for #{auth.inspect}"
    else
      # Log unauthorized logins to error.
      Rails.logger.error "Unauthorized user attemped login: #{auth.inspect}"
    end
  end
end

class Avalon::MissingUserId < StandardError; end
class Avalon::DeletedUserId < StandardError; end
