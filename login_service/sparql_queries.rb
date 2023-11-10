require_relative '../lib/mu/auth-sudo'

USERS_GRAPH = ENV['USERS_GRAPH'] || "http://mu.semte.ch/application"
SESSIONS_GRAPH = ENV['SESSIONS_GRAPH'] || "http://mu.semte.ch/application"

module LoginService
  module SparqlQueries

    def select_salted_password_and_salt_by_nickname(nickname)
      query =  " SELECT ?uuid ?uri ?password ?salt WHERE {" + "\n"
      query += "   GRAPH <#{USERS_GRAPH}> {" + "\n"
      query += "     ?uri a <#{RDF::Vocab::FOAF.OnlineAccount}> ;" + "\n"
      query += "        <#{RDF::Vocab::FOAF.accountName}> #{nickname.downcase.sparql_escape} ;" + "\n"
      query += "        <#{MU_ACCOUNT.status}> <#{MU_ACCOUNT['status/active']}> ;" + "\n"
      query += "        <#{MU_ACCOUNT.password}> ?password ;" + "\n"
      query += "        <#{MU_ACCOUNT.salt}> ?salt ;" + "\n"
      query += "        <#{MU_CORE.uuid}> ?uuid ." + "\n"
      query += "   }" + "\n"
      query += " }" + "\n"
      Mu::AuthSudo.query(query)
    end

    def select_roles(account)
      query = " SELECT (GROUP_CONCAT(?role; SEPARATOR = ',') as ?roles) WHERE {" + "\n"
      query += "   GRAPH <#{USERS_GRAPH}> {" + "\n"
      query += "     <#{account}> <#{MU_EXT.role}> ?uri ." + "\n"
      query += "     ?uri <#{MU_EXT.name}> ?role ." + "\n"
      query += "   }" + "\n"
      query += " }" + "\n"
      Mu::AuthSudo.query(query)
    end

    def remove_old_sessions(session)
      query =  " DELETE {" + "\n"
      query += "   GRAPH <#{SESSIONS_GRAPH}> {" + "\n"
      query += "     <#{session}> <#{MU_SESSION.account}> ?account ;" + "\n"
      query += "                  <#{MU_CORE.uuid}> ?id ;" + "\n"
      query += "                  <#{DCTERMS.modified}> ?modified ;" + "\n"
      query += "                  <#{MU_EXT.sessionRole}> ?role ." + "\n"
      query += "   }" + "\n"
      query += " }" + "\n"
      query += " WHERE {" + "\n"
      query += "   GRAPH <#{SESSIONS_GRAPH}> {" + "\n"
      query += "     <#{session}> <#{MU_SESSION.account}> ?account ;" + "\n"
      query += "                  <#{MU_CORE.uuid}> ?id ;" + "\n"
      query += "                  <#{DCTERMS.modified}> ?modified ;" + "\n"
      query += "                  <#{MU_EXT.sessionRole}> ?role ." + "\n"
      query += "   }" + "\n"
      query += " }" + "\n"
      Mu::AuthSudo.update(query)
    end

    def insert_new_session_for_account(account, session_uri, session_id, roles)
      roles_string = roles.map{|r| r.sparql_escape}.join(", ")
      query = " PREFIX ext: <http://mu.semte.ch/vocabularies/ext/>" + "\n"
      query += " INSERT DATA {" + "\n"
      query += "   GRAPH <#{SESSIONS_GRAPH}> {" + "\n"
      query += "     <#{session_uri}> <#{MU_SESSION.account}> <#{account}> ;" + "\n"
      query += "                      <#{MU_CORE.uuid}> #{session_id.sparql_escape} ;" + "\n"
      if roles_string.length > 0
        query += "                      ext:sessionRole #{roles_string} ." + "\n"
      end
      query += "   }" + "\n"
      query += " }" + "\n"
      Mu::AuthSudo.update(query)
    end

    def select_account_by_session(session)
      query =  " SELECT ?uuid ?account WHERE {" + "\n"
      query += "   GRAPH <#{SESSIONS_GRAPH}> {" + "\n"
      query += "     <#{session}> <#{MU_SESSION.account}> ?account ." + "\n"
      query += "   }" + "\n"
      query += "   GRAPH <#{USERS_GRAPH}> {" + "\n"
      query += "     ?account <#{MU_CORE.uuid}> ?uuid ;" + "\n"
      query += "              a <#{RDF::Vocab::FOAF.OnlineAccount}> ." + "\n"
      query += "   }" + "\n"
      query += " }" + "\n"
      Mu::AuthSudo.query(query)
    end

    def select_current_session(account)
      query =  " SELECT ?uri WHERE {" + "\n"
      query += "   GRAPH <#{SESSIONS_GRAPH}> {" + "\n"
      query += "     ?uri <#{MU_SESSION.account}> <#{account}> ;" + "\n"
      query += "          <#{MU_CORE.uuid}> ?id ." + "\n"
      query += "   }" + "\n"
      query += " }" + "\n"
      Mu::AuthSudo.query(query)
    end

    def select_current_session_ext(account)
      query =  " PREFIX ext: <http://mu.semte.ch/vocabularies/ext/>" + "\n"
      query += " SELECT ?uri (GROUP_CONCAT(?role; SEPARATOR = ',') as ?roles)" + "\n"
      query += " WHERE {" + "\n"
      query += "   GRAPH <#{SESSIONS_GRAPH}> {" + "\n"
      query += "     ?uri <#{MU_SESSION.account}> <#{account}> ;" + "\n"
      query += "          <#{MU_CORE.uuid}> ?id ;" + "\n"
      query += "          ext:sessionRole ?role ." + "\n"
      query += "   }" + "\n"
      query += " } GROUP BY ?uri" + "\n"
      Mu::AuthSudo.query(query)
    end

    def delete_current_session(account)
      query = " DELETE {" + "\n"
      query += "   GRAPH <#{SESSIONS_GRAPH}> {" + "\n"
      query += "     ?session <#{MU_SESSION.account}> <#{account}> ;" + "\n"
      query += "              <#{MU_CORE.uuid}> ?id ." + "\n"
      query += "   }" + "\n"
      query += " }" + "\n"
      query += " WHERE {" + "\n"
      query += "   GRAPH <#{SESSIONS_GRAPH}> {" + "\n"
      query += "     ?session <#{MU_SESSION.account}> <#{account}> ;" + "\n"
      query += "              <#{MU_CORE.uuid}> ?id ." + "\n"
      query += "   }" + "\n"
      query += " }" + "\n"
      Mu::AuthSudo.update(query)
    end

    def update_modified(session, modified = DateTime.now)
      query = " DELETE {" + "\n"
      query += "   GRAPH <#{SESSIONS_GRAPH}> {" + "\n"
      query += "     <#{session}> <#{RDF::Vocab::DC.modified}> ?modified ." + "\n"
      query += "   }" + "\n"
      query += " }" + "\n"
      query += " WHERE {" + "\n"
      query += "   GRAPH <#{SESSIONS_GRAPH}> {" + "\n"
      query += "     <#{session}> <#{RDF::Vocab::DC.modified}> ?modified ." + "\n"
      query += "   }" + "\n"
      query += " }" + "\n"
      Mu::AuthSudo.update(query)

      query =  " INSERT DATA {" + "\n"
      query += "   GRAPH <#{SESSIONS_GRAPH}> {" + "\n"
      query += "     <#{session}> <#{RDF::Vocab::DC.modified}> #{modified.sparql_escape} ." + "\n"
      query += "   }" + "\n"
      query += " }" + "\n"
      Mu::AuthSudo.update(query)
    end

  end
end
