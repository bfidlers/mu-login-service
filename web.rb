require 'digest'
require 'securerandom'

configure do
  set :salt, ENV['MU_APPLICATION_SALT']
end


###
# POST /sessions
#
# Body    {"data":{"type":"sessions","attributes":{"nickname":"john_doe","password":"secret"}}}
# Returns 200 on successful login
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
  
  rewrite_url = rewrite_url_header(request)
  error('X-Rewrite-URL header is missing') if rewrite_url.nil?


  ###
  # Validate request
  ###

  request.body.rewind
  body = JSON.parse request.body.read
  data = body['data']
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
  db_password = account[:password].to_s
  password = Digest::MD5.new << attributes['password'] + settings.salt + account[:salt].to_s

  error('This combination of username and password cannot be found.') unless db_password == password.hexdigest


  ###
  # Remove old sessions
  ###
  remove_old_sessions_for_account(account[:uri].to_s)


  ###
  # Insert new session
  ###

  session_id = SecureRandom.uuid
  insert_new_session_for_account(account[:uri].to_s, session_uri, session_id)
  update_modified(session_uri)

  status 201
  {
    links: {
      self: rewrite_url.chomp('/') + '/current'
    },
    data: {
      type: 'sessions',
      id: session_id,
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

  session_uri = session_id_header()
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
end


###
# Helpers
###

helpers do

  def select_salted_password_and_salt_by_nickname(nickname)
    query =  " SELECT ?uri ?password ?salt FROM <#{settings.graph}> WHERE {"
    query += "   ?uri a <#{RDF::Vocab::FOAF.OnlineAccount}> ; "
    query += "        <#{RDF::Vocab::FOAF.accountName}> '#{nickname.downcase}' ; "
    query += "        <#{MU['account/status']}> <#{MU['account/status/active']}> ; "
    query += "        <#{MU['account/password']}> ?password ; "
    query += "        <#{MU['account/salt']}> ?salt . "
    query += " }"
    query(query)
  end

  def remove_old_sessions_for_account(account)
    query =  " WITH <#{settings.graph}> "
    query += " DELETE {"
    query += "   ?session <#{MU['session/account']}> <#{account}> ;"
    query += "            <#{MU.uuid}> ?id . "
    query += " }"
    query += " WHERE {"
    query += "   ?session <#{MU['session/account']}> <#{account}> ;"
    query += "            <#{MU.uuid}> ?id . "
    query += " }"
    update(query)
  end

  def insert_new_session_for_account(account, session_uri, session_id)
    query =  " INSERT DATA {"
    query += "   GRAPH <#{settings.graph}> {"
    query += "     <#{session_uri}> <#{MU['session/account']}> <#{account}> ;"
    query += "                      <#{MU.uuid}> \"#{session_id}\" ."
    query += "   }"
    query += " }"
    update(query)
  end
  
  def select_account_by_session(session)
    query =  " SELECT ?account FROM <#{settings.graph}> WHERE {"
    query += "   <#{session}> <#{MU['session/account']}> ?account ."
    query += "   ?account a <#{RDF::Vocab::FOAF.OnlineAccount}> ."
    query += " }"
    query(query)
  end
  
  def select_current_session(account)
    query =  " SELECT ?uri FROM <#{settings.graph}> WHERE {"
    query += "   ?uri <#{MU['session/account']}> <#{account}> ;"
    query += "        <#{MU.uuid}> ?id . "
    query += " }"
    query(query)
  end

  def delete_current_session(account)
    query =  " WITH <#{settings.graph}> "
    query += " DELETE {"
    query += "   ?session <#{MU['session/account']}> <#{account}> ;"
    query += "            <#{MU.uuid}> ?id . "
    query += " }"
    query += " WHERE {"
    query += "   ?session <#{MU['session/account']}> <#{account}> ;"
    query += "            <#{MU.uuid}> ?id . "
    query += " }"
    update(query)
  end
  
end
