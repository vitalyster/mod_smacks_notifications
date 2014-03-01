local st = require "util.stanza";
local xmlns_notifications_gcm = "http://sawim.ru/notifications#gcm";

local http = require "net.http";
local gcm_uri = "https://android.googleapis.com/gcm/send";
local GCM_API_KEY = module:get_option("gcm_api_key", nil);

module:add_feature(xmlns_notifications_gcm);

function handle_notifications_command(event)
   local session, stanza = event.origin, event.stanza;
   if stanza.tags[1].name == "register" then
      local request = stanza.tags[1];
      local regid = request.attr.regid;
      if regid == nil then
	 -- bad request
	 session.send(st.error_reply(stanza, "modify", "bad-request"));
      else
	 -- add device to session
	 session.regid = regid
	 module:log("debug", "Assigned GCM regid=%s to session %s", session.regid, session.resumption_token)
	 session.send(st.reply(stanza));
      end
      return true;
   elseif stanza.tags[1].name == "unregister" then
      -- remove device
      session.regid = nil
      module:log("debug", "GCM device unregistered from session %s", session.resumption_token);
      session.send(st.reply(stanza));
      return true;
   end
end

module:hook("iq-set/self/"..xmlns_notifications_gcm..":register", handle_notifications_command);
module:hook("iq-set/self/"..xmlns_notifications_gcm..":unregister", handle_notifications_command);

function handle_smacks_message(event)
   local session, stanza = event.origin, event.stanza;
   module:log("debug", "message to session %s", session.resumption_token);
   if session.regid ~= nil then
      -- send message to GCM
      if GCM_API_KEY != nil then
	 message_body = http.urlencode(stanza:get_child("body"):get_text());
	 http.request(gcm_uri, {
			 headers = {name = "Authorization", value = GCM_API_KEY},
			 body = http.formencode({
						   name = "data.message", value = message_body,
						   name = "recipients_ids", value = session.regid,
						   name = "collapse_key", value ="New messages"
			 })
			       },
		      function(response, code, request) 
			 module:log("debug", "GCM status %d", code)
	 end);
      else
	 module:log("error", "GCM API key not defined");
      end
   end
end

module:hook("smacks-message", handle_smacks_message);
