--------------------------------------------------------------------------------
-- | Converts HTTP requests to Socket.IO requests
{-# LANGUAGE OverloadedStrings #-}
module Web.SocketIO.Request (parseHTTPRequest) where

--------------------------------------------------------------------------------
import              Web.SocketIO.Types
import              Web.SocketIO.Protocol

--------------------------------------------------------------------------------
import              Control.Applicative                     ((<$>))   
import qualified    Network.Wai                             as Wai
import              Network.HTTP.Types                      (Method)

--------------------------------------------------------------------------------
-- | Information of a HTTP reqeust we need
type RequestInfo = (Method, Path, Framed Message)

--------------------------------------------------------------------------------
-- | Extracts from HTTP reqeusts
retrieveRequestInfo :: Wai.Request -> IO RequestInfo
retrieveRequestInfo request = do

    framedMessages <- parseHTTPBody request

    let path = parsePath (Wai.rawPathInfo request)

    return 
        (   Wai.requestMethod request
        ,   path 
        ,   framedMessages
        )

--------------------------------------------------------------------------------
-- | Converts to SocketIO request
processRequestInfo :: RequestInfo -> [Request]
processRequestInfo ("GET" , (WithoutSession _ _)         , _              ) = [Handshake]
processRequestInfo ("GET" , (WithSession _ _ _ sessionID), _              ) = [Connect sessionID]
processRequestInfo ("POST", (WithSession _ _ _ sessionID), Framed messages) = requests
    where   requests = foldr extractEvent [] messages
            extractEvent (MsgEvent _ _ event) acc = Emit sessionID event : acc
            extractEvent _                    acc = acc
processRequestInfo (_     , (WithSession _ _ _ sessionID), _              ) = [Disconnect sessionID]
processRequestInfo _    = error "error parsing http request"
 
--------------------------------------------------------------------------------
-- | The request part
parseHTTPRequest :: Wai.Request -> IO [Request]
parseHTTPRequest request = fmap processRequestInfo (retrieveRequestInfo request)

--------------------------------------------------------------------------------
-- | The message part
parseHTTPBody :: Wai.Request -> IO (Framed Message)
parseHTTPBody req = parseFramedMessage <$> Wai.lazyRequestBody req