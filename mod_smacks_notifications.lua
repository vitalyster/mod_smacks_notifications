local st = require "util.stanza";
local xmlns_notifications_gcm = "http://sawim.ru/notifications#gcm";

local http = require "net.http";
local json_encode = require"util.json".encode;
local sessionmanager = require "core.sessionmanager";

require "pack"
local bpack = string.pack
local gcm_uri = "https://android.googleapis.com/gcm/send";
local GCM_API_KEY = module:get_option("gcm_api_key", nil);

module:add_feature(xmlns_notifications_gcm);

require "socket";
require "ssl";

local xmlns_notifications_apn = "http://sawim.ru/notifications#apn";
local apn_endpoint_sandbox = "gateway.sandbox.push.apple.com";
local apn_keyfile = module:get_option("apn_keyfile", nil); 
local apn_certificate = module:get_option("apn_certificate", nil);
module:add_feature(xmlns_notifications_apn);

function hex(s)
 s=string.gsub(s,"(.)",function (x) return string.format("%02X",string.byte(x)) end)
 return s
end
function string.fromhex(str)
    return (str:gsub('..', function (cc)
        return string.char(tonumber(cc, 16))
    end))
end

function handle_notifications_command(event)
        local session, stanza = event.origin, event.stanza;
        if stanza.tags[1].name == "register" then
		local request = stanza.tags[1];
                local regid = request.attr.regid;
                if regid == nil then
			local device_token = request.attr.token;
			if device_token == nil then
				-- bad request
	                        session.send(st.error_reply(stanza, "modify", "bad-request"));
			else
				-- clear old sessions
				for j, s in pairs(full_sessions) do
					if full_sessions[j].device_token == device_token then
						module:log("debug", "session %s will be replaced", full_sessions[j].full_jid);
						full_sessions[j].device_token = nil;
						sessionmanager.destroy_session(full_sessions[j]);	
					end
				end
				-- add apple device
				session.device_token = device_token;
				module:log("debug", "Assigned APN device token=%s to %s", session.device_token, stanza.attr.from)
	                        session.send(st.reply(stanza)); 
			end
                else
			-- add google device to session
			session.regid = regid
			module:log("debug", "Assigned GCM regid=%s to %s", session.regid, stanza.attr.from);
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

module:hook("iq-set/self/"..xmlns_notifications_apn..":register", handle_notifications_command);
module:hook("iq-set/self/"..xmlns_notifications_apn..":unregister", handle_notifications_command);

local open_connections = {};

local function new_session(jid, sid, conn)
	if not open_connections[jid] then
		open_connections[jid] = {};
	end
	open_connections[jid][sid] = conn;
end
local function close_session(jid, sid)
	if open_connections[jid] then
		open_connections[jid][sid] = nil;
		if next(open_connections[jid]) == nil then
			open_connections[jid] = nil;
		end
		return true;
	end
end


function handle_smacks_message(event)
        local session, stanza = event.origin, event.stanza;
        module:log("debug", "message to %s", session.full_jid);
	if session.regid ~= nil then
		if GCM_API_KEY ~= nil then
			-- send message to GCM
			message_body = http.urlencode(stanza:get_child("body"):get_text());
			json_body = json_encode {
                        	        collapse_key = "messages",
                                	registration_ids = {session.regid},
	                                data = { message = message_body, 
						 message_from = stanza.attr.from, 
                                                 message_type = stanza.attr.type 
                                               };
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
			return;
		end
	else
		if session.device_token ~= nil then
				if apn_keyfile == nil or apn_certificate == nil then
					module:log("error", "apn_keyfile or apn_certificate not configured");
					return;
				end
				message_body = stanza:get_child("body"):get_text();
				json_body = json_encode {
					aps = {alert = message_body, sound = "default"}
					};
				local listener = {};
				function listener.onconnect(conn)
					local conn = open_connections[stanza.attr.from][session.resumption_token];
                                        if conn then
                                                module:log("debug", "APN message to %s", session.full_jid);
						payload = bpack("b>P>P", 0, session.device_token:fromhex(), json_body);
						module:log("debug", hex(payload));
						conn:write(payload);
                                        else
                                                module:log("debug", "session %s not found", session.resumption_token);
                                        end;
                                end
                                function listener.onincoming(conn, data)
					local conn = open_connections[stanza.attr.from][session.resumption_token];
					if conn then
                                        -- 	module:log("debug", data)
					--	close_session(stanza.attr.from, session.resumption_token);
					else
						module:log("debug", "session %s not found", session.resumption_token);
					end;
                                end
				local conn, err = socket.tcp();
				conn:settimeout(0);
				conn:connect(apn_endpoint_sandbox, 2195);
                                local sslctx = {
				 mode = "client",
				 protocol = "tlsv1",
				 capath = "/etc/ssl/certs",
				 options = "all",
				 key = apn_keyfile,
				 certificate = apn_certificate,
				 verify="peer",

				};
				conn = server.wrapclient(conn, apn_endpoint_sandbox, 2195, listener, "*a", sslctx );
				new_session(stanza.attr.from, session.resumption_token, conn);
		end
	end
end

module:hook("smacks-message", handle_smacks_message);
