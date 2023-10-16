require 'jwt'

class UsersController < ApplicationController
  namespace "/users" do
    post "/authenticate" do
      # Modify params to show all user attributes
      params["display"] = User.attributes.join(",")
      if $SSO_ENABLED
        user = sso_auth
      else
        user = password_auth
      end

      user.show_apikey = true
      reply user
    end

    ##
    # This endpoint will create a token and store it on the user
    # An email is generated with this token, which allows the user
    # to click and login to the UI. The token can then be provided to
    # the /reset_password endpoint to actually reset the password.
    post "/create_reset_password_token" do
      email    = params["email"]
      username = params["username"]
      user = LinkedData::Models::User.where(email: email, username: username).include(LinkedData::Models::User.attributes).first
      error 404, "User not found" unless user
      reset_token = token(36)
      user.resetToken = reset_token
      if user.valid?
        user.save(override_security: true)
        LinkedData::Utils::Notifications.reset_password(user, reset_token)
      else
        error 422, user.errors
      end
      halt 204
    end

    ##
    # Passing an email, username, and token to this endpoint will
    # authenticate the user and provide back a full user object which
    # can be used to log a user in. This will allow them to change their
    # password and update the user object.
    post "/reset_password" do
      email             = params["email"] || ""
      username          = params["username"] || ""
      token             = params["token"] || ""
      params["display"] = User.attributes.join(",") # used to serialize everything via the serializer
      user = LinkedData::Models::User.where(email: email, username: username).include(User.goo_attrs_to_load(includes_param)).first
      error 404, "User not found" unless user
      if token.eql?(user.resetToken)
        user.show_apikey = true
        reply user
      else
        error 403, "Password reset not authorized with this token"
      end
    end

    # Display all users
    get do
      check_last_modified_collection(User)
      reply User.where.include(User.goo_attrs_to_load(includes_param)).to_a
    end

    # Display a single user
    get '/:username' do
      user = User.find(params[:username]).first
      error 404, "Cannot find user with username `#{params['username']}`" if user.nil?
      check_last_modified(user)
      user.bring(*User.goo_attrs_to_load(includes_param))
      reply user
    end

    # Create user
    post do
      create_user
    end

    # Users get created via put because clients can assign an id (POST is only used where servers assign ids)
    put '/:username' do
      create_user
    end

    # Update an existing submission of an user
    patch '/:username' do
      user = User.find(params[:username]).include(User.attributes).first
      populate_from_params(user, params)
      if user.valid?
        user.save
      else
        error 422, user.errors
      end
      halt 204
    end

    # Delete a user
    delete '/:username' do
      User.find(params[:username]).first.delete
      halt 204
    end

    private

    def password_auth
      user_id = params["user"]
      user_password = params["password"]
      user = User.find(user_id).include(User.goo_attrs_to_load(includes_param) + [:passwordHash]).first
      authenticated = user.authenticate(user_password) unless user.nil?
      error 401, "Username/password combination invalid" unless authenticated
      user
    end

    def sso_auth
      bearer_token = params["token"]
      error 401, "No bearer token provided" unless bearer_token

      begin
        decoded_token = LinkedData::Security::Authorization.decodeJWT(bearer_token)
      rescue JWT::DecodeError => e
        error 401, "Failed to decode JWT token: " + e.message
      end
      token_payload = decoded_token[0]

      user_id = token_payload[LinkedData.settings.oauth2_username_claim]
      given_name = token_payload[LinkedData.settings.oauth2_given_name_claim]
      family_name = token_payload[LinkedData.settings.oauth2_family_name_claim]
      email = token_payload[LinkedData.settings.oauth2_email_claim]

      user = User.find(user_id).include(User.goo_attrs_to_load(includes_param)).first

      if user.nil? # first-time access, register new user
        user_creation_params = {
          username: user_id,
          firstName: given_name,
          lastName: family_name,
          email: email,
          password: SecureRandom.hex(16)
        }

        user = instance_from_params(User, user_creation_params)
        save_user(user)
      end
      user
    end

    def token(len)
      chars = ("a".."z").to_a + ("A".."Z").to_a + ("1".."9").to_a
      token = ""
      1.upto(len) { |i| token << chars[rand(chars.size-1)] }
      token
    end

    def create_user
      params ||= @params
      user = User.find(params["username"]).first
      error 409, "User with username `#{params["username"]}` already exists" unless user.nil?
      user = instance_from_params(User, params)
      save_user(user)
      reply 201, user
    end

    def save_user(user)
      if user.valid?
        user.save
        # Send an email to the administrator to warn him about the newly created user
        begin
          if !LinkedData.settings.admin_emails.nil? && !LinkedData.settings.admin_emails.empty?
            LinkedData::Utils::Notifications.new_user(user)
          end
        rescue Exception => e
        end
      else
        error 422, user.errors
      end
    end
  end
end
