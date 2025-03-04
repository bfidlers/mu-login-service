require 'bcrypt'
require_relative 'login_service/sparql_queries.rb'

configure do
  set :salt, ENV['MU_APPLICATION_SALT']
end

###
# Vocabularies
###

MU_ACCOUNT = RDF::Vocabulary.new(MU.to_uri.to_s + 'account/')
MU_SESSION = RDF::Vocabulary.new(MU.to_uri.to_s + 'session/')
MU_EXT = RDF::Vocabulary.new(MU.to_uri.to_s + 'ext/')
DCTERMS = RDF::Vocabulary.new("http://purl.org/dc/terms/")


###
# POST /sessions
#
# Body    {"data":{"type":"sessions","attributes":{"nickname":"john_doe","password":"secret"}}}
# Returns 201 on successful login
#         400 if session header is missing
#         400 on login failure (incorrect user/password or inactive account)
###
post '/sessions/?' do
  content_type 'application/vnd.api+json'


  ###
  # Validate headers
  ###
  validate_json_api_content_type(request)

  session_uri = session_id_header(request)
  error('Session header is missing') if session_uri.nil?

  rewrite_url = rewrite_url_header(request) || ''

  ###
  # Validate request
  ###

  data = @json_body['data']
  attributes = data['attributes']

  validate_resource_type('sessions', data)
  error('Id paramater is not allowed', 403) if not data['id'].nil?

  error('Nickname is required') if attributes['nickname'].nil?
  error('Password is required') if attributes['password'].nil?

  ###
  # Validate login
  ###

  result = select_salted_password_and_salt_by_nickname(attributes['nickname'])

  error('This combination of username and password cannot be found.') if result.empty?

  account = result.first
  db_password = BCrypt::Password.new account[:password].to_s
  password = attributes['password'] + settings.salt + account[:salt].to_s

  error('This combination of username and password cannot be found.') unless db_password == password


  ###
  # Remove old sessions
  ###
  remove_old_sessions(session_uri)


  ###
  # Insert new session
  ###

  session_id = generate_uuid()

  roles = select_roles(account[:uri].to_s)
  parsed_roles = roles.empty? ? [] : roles.first[:roles].to_s.split(',')

  insert_new_session_for_account(account[:uri].to_s, session_uri, session_id, parsed_roles)
  update_modified(session_uri)
  status 201
  headers['mu-auth-allowed-groups'] = 'CLEAR'
  {
    links: {
      self: rewrite_url.chomp('/') + '/current'
    },
    data: {
      type: 'sessions',
      id: session_id,
      attributes: {
        roles: parsed_roles
      },
      relationships: {
        account: {
          links: {
            related: "/accounts/#{account[:uuid]}"
          },
          data: {
            type: "accounts",
            id: account[:uuid]
          }
        }
      }
    }
  }.to_json
end


###
# DELETE /sessions/current
#
# Returns 204 on successful logout
#         400 if session header is missing or session header is invalid
###
delete '/sessions/current/?' do
  content_type 'application/vnd.api+json'

  ###
  # Validate session
  ###

  session_uri = session_id_header(request)
  error('Session header is missing') if session_uri.nil?


  ###
  # Get account
  ###

  result = select_account_by_session(session_uri)
  error('Invalid session') if result.empty?
  account = result.first[:account].to_s


  ###
  # Remove session
  ###

  result = select_current_session(account)
  result.each { |session| update_modified(session[:uri]) }
  delete_current_session(account)

  status 204
  headers['mu-auth-allowed-groups'] = 'CLEAR'
end


###
# GET /sessions/current
#
# Returns 204 if current session exists
#         400 if session header is missing or session header is invalid
###
get '/sessions/current/?' do
  content_type 'application/vnd.api+json'

  ###
  # Validate session
  ###

  session_uri = session_id_header(request)
  error('Session header is missing') if session_uri.nil?


  ###
  # Get account
  ###

  result = select_account_by_session(session_uri)
  error('Invalid session') if result.empty?
  account = result.first

  rewrite_url = rewrite_url_header(request)

  result_session = select_current_session_ext(account[:account].to_s)
  parsed_roles = result_session.empty? ? [] : result_session.first[:roles].to_s.split(',')

  status 200
 {
    links: {
      self: rewrite_url.chomp('/')
    },
    data: {
      type: 'sessions',
      id: session_uri,
      attributes: {
        roles: parsed_roles
      },
      relationships: {
        account: {
          links: {
            related: "/accounts/#{account[:uuid]}"
          },
          data: {
            type: "accounts",
            id: account[:uuid]
          }
        }
      }
    }
  }.to_json
end


###
# Helpers
###

helpers LoginService::SparqlQueries
