mod_smacks_notifications
========================

Apple Push Notifications and Google Cloud Messaging module for Prosody

Requirements and installation
-----------------------------
1. [Prosody](http://prosody.im)
2. [mod_smacks](https://code.google.com/p/prosody-modules/wiki/mod_smacks)
3. `smacks_hibernation_time` should be set much higher than default value, e.g. `86400` (session will stay 24 hours)
4. patch for mod_smacks:
```lua
--- a/mod_smacks/mod_smacks.lua Sat Feb 22 13:26:22 2014 +0100
+++ b/mod_smacks/mod_smacks.lua Sun Mar 02 21:04:40 2014 +0000
@@ -93,6 +93,9 @@
                        queue[#queue+1] = cached_stanza;
                end
                if session.hibernating then
+                       if stanza.name == "message" and stanza:get_child("body") ~= nil then
+                               module:fire_event("smacks-message", {origin = session, stanza = stanza});
+                       end
                        -- The session is hibernating, no point in sending the stanza
                        -- over a dead connection.  It will be delivered upon resumption.
                        return true;
```
Configuration parameters
------------------------
`gcm_api_key` - Google Cloud Messaging key for your Android application (you should generate it in Google API Console)

`apn_key_file` and `apn_certificate` - APNS key and certificate for your iOS application

Usage
-----
### Determining server support 

When server have `mod_smacks_notifications` enabled it will advertise 
`http://sawim.ru/notifications#gcm` and `http://sawim.ru/notifications#apn` features:
```xml
C: <iq type="get" id="123456">
C: <query xmlns="http://jabber.org/protocol/disco#info"/>
C: </iq>
S: <iq type="result" id="123456">
S: [...]
S: <feature var="http://sawim.ru/notifications#gcm"/>
S: <feature var="http://sawim.ru/notifications#apn"/>
S: [...]
S: </iq>
```

Of course, server and should also supports [Stream Management](http://xmpp.org/extensions/xep-0198.html) protocol and it *must* be enabled in the client session before it can enable push notifications


### Registering device for receiving notifications

Android client must send `deviceid` received when he register Cloud Messaging session
```xml
C: <iq id="234567" type="set">
C: <register xmlns="http://sawim.ru/notifications#gcm" 
C: regid="{your_device_id}"/>
C: </iq>
```
And iOS client must send similar device token received when he registered APNS notifications
```xml
C: <iq id="234567" type="set">
C: <register xmlns="http://sawim.ru/notifications#gcm"
C: token="{device_token_hex}"/>
C: </iq>
```

### Preferences

User may want to filter events to receive. 
At now you can select `groupchat`, `roster` or `off`:
```xml
C: <iq id="234567" type="set">
C: <register [...]>
C: <prefs default="roster" />
C: </register>
C: </iq>
```
In this case user will receive only roster messages. 
You can also temporarily disable notifications with `prefs="off"` 
or completely unregister device
```xml
C: <iq id="345678" type="set">
C: <unregister xmlns="http://sawim.ru/notifications#gcm" />
C: </iq>
```

In all cases you must receive `result` or `error` from server in reply to each query:
```xml
S: <iq id="345678" type="result" />
```
