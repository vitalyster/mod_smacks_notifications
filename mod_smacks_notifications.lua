local st = require "util.stanza";
local xmlns_notifications_gcm = "http://sawim.ru/notifications#gcm";

local http = require "net.http";
local json_encode = require"util.json".encode;

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
		module:log("debug", "GCM regid unregistered from session %s", session.resumption_token);
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
		if GCM_API_KEY != nil then
			-- send message to GCM
			message_body = http.urlencode(stanza:get_child("body"):get_text());
			json_body = json_encode {
                        	        collapse_key = "messages",
                                	registration_ids = {session.regid},
	                                data = { message = message_body, message_from = stanza.attr.from };
        	                        };
               		module:log("debug", json_body);
			http.request(gcm_uri, {
				headers = {
					["Authorization"] = "key="..GCM_API_KEY;
					["Content-Type"] = "application/json";
				};
				body = json_body;
				}, function (resp, code, request)
					module:log("debug", "GCM status %d", code);
					tostring(resp);
				    end
				);
		else
			module:log("error", "GCM API key not defined");
		end
	end
end

module:hook("smacks-message", handle_smacks_message);
