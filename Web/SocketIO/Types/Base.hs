--------------------------------------------------------------------------------
-- | Cluster fuck of unorganized data types
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE OverloadedStrings #-}

module Web.SocketIO.Types.Base where

--------------------------------------------------------------------------------
import              Web.SocketIO.Types.Log
import              Web.SocketIO.Types.String
import              Web.SocketIO.Types.Event

--------------------------------------------------------------------------------
import              Control.Applicative
import              Control.Concurrent.MVar.Lifted
import              Control.Concurrent.Chan.Lifted
import              Control.Monad.Reader       
import              Control.Monad.Writer
import              Control.Monad.Base
import qualified    Data.HashMap.Strict                     as H
import              Data.IORef.Lifted
import              System.IO                               (Handle)

--------------------------------------------------------------------------------
-- | Information of a individual client; established after `Web.SocketIO.Types.Request.Handshake`, torn down after `Web.SocketIO.Types.Request.Disconnect`.
data Session = Session
    {   sessionSessionID :: SessionID   -- ^ Identifier
    ,   sessionState :: SessionState    -- ^ State
    ,   sessionChannelHub :: ChannelHub -- ^ Output channels
    ,   sessionListener :: [Listener]   -- ^ Server-side listeners
    ,   sessionTimeoutVar :: MVar Bool  -- ^ TTL
    }

instance Show Session where
    show (Session i s _ _ _) = "Session " 
                            ++ fromByteString i 
                            ++ " [" ++ show s ++ "]"

--------------------------------------------------------------------------------
-- | Session ID
type SessionID = ByteString 

--------------------------------------------------------------------------------
-- | Session table, consists of `SessionID`, `Session` pairs.
type SessionTable = H.HashMap SessionID Session

--------------------------------------------------------------------------------
-- | Session states
data SessionState = Connecting  -- ^ after `Web.SocketIO.Types.Request.Handshake`
                  | Connected   -- ^ after `Web.SocketIO.Types.Request.Connect`.
                  deriving (Show, Eq)

--------------------------------------------------------------------------------
-- | Fine-grained session layer requests
data SessionAction   = SessionHandshake
                     | SessionConnect
                     | SessionPolling
                     | SessionEmit Event
                     | SessionDisconnect

--------------------------------------------------------------------------------
-- | Server-wide configurations
data Env = Env { 
    envSessionTableRef :: IORef SessionTable, 
    envHandler :: HandlerM (), 
    envConfiguration :: Configuration,
    envLogChannel :: Chan ByteString,
    envGlobalChannel :: Chan Package
}

--------------------------------------------------------------------------------
-- | Collection of unbounded FIFO channels.
data ChannelHub = ChannelHub
    {   channelHubLocal :: Chan Package
    ,   channelHubGlobal :: Chan Package
    ,   channelHubOutput :: Chan Package
    ,   channelHubLog :: Chan ByteString
    }

--------------------------------------------------------------------------------
-- | Defines behaviors of a Socket.IO server
data Configuration = Configuration
    {   transports :: [Transport]
    ,   logLevel :: Int
    ,   logTo :: Handle
    ,   heartbeats :: Bool
    ,   closeTimeout :: Int
    ,   heartbeatTimeout :: Int
    ,   heartbeatInterval :: Int
    ,   pollingDuration :: Int
    } deriving Show
    
--------------------------------------------------------------------------------
-- | Port number for a standalone Socket.IO server.
type Port = Int

--------------------------------------------------------------------------------
-- | Triggered by an `Web.SocketIO.Types.Request.Event`.
type Listener = (EventName, CallbackM ())

--------------------------------------------------------------------------------
-- | Class for handy `SessionID` getter.
class HasSessionID m where
    getSessionID :: m SessionID

--------------------------------------------------------------------------------
-- | Environment carried by `HandlerM`
data HandlerEnv = HandlerEnv
    {   handlerEnvChannelHub :: ChannelHub
    ,   handlerEnvSessionID :: SessionID
    }

--------------------------------------------------------------------------------
-- | Environment carried by `CallbackM`
data CallbackEnv = CallbackEnv
    {   callbackEnvEventName :: EventName
    ,   callbackEnvPayload :: [Payload]
    ,   callbackEnvChannelHub :: ChannelHub
    ,   callbackEnvSessionID :: SessionID
    }

--------------------------------------------------------------------------------
-- | Capable of both sending and receiving events.
--
-- Use 'liftIO' if you wanna do some IO here.
newtype HandlerM a = HandlerM { runHandlerM :: (ReaderT HandlerEnv (WriterT [Listener] IO)) a }
    deriving (Monad, Functor, Applicative, MonadIO, MonadWriter [Listener], MonadReader HandlerEnv, MonadBase IO)

--instance HasSessionID HandlerM where
--    getSessionID = handlerEnvSessionID <$> ask

--------------------------------------------------------------------------------
-- | Capable of only sending events.
--
-- Use 'liftIO' if you wanna do some IO here.
newtype CallbackM a = CallbackM { runCallbackM :: (WriterT [Event] (ReaderT CallbackEnv IO)) a }
    deriving (Monad, Functor, Applicative, MonadIO, MonadWriter [Event], MonadReader CallbackEnv, MonadBase IO)

instance HasSessionID CallbackM where
    getSessionID = CallbackM . lift $ callbackEnvSessionID <$> ask

--------------------------------------------------------------------------------
-- | Sending events
class Publisher m where
    -- | Sends a message to the socket that starts it.
    --
    -- @
    -- `emit` \"launch\" [\"missile\", \"nuke\"] 
    -- @
    emit    :: EventName            -- ^ name of event to trigger
            -> [Text]               -- ^ message to carry with
            -> m ()

    -- | Sends a message to everyone else except for the socket that starts it.
    --
    -- @
    -- `broadcast` \"hide\" [\"nukes coming!\"] 
    -- @
    broadcast   :: EventName        -- ^ name of event to trigger
                -> [Text]           -- ^ message to carry with
                -> m ()

    -- | 

instance Publisher HandlerM where
    emit event reply = do
        channel <- channelHubLocal . handlerEnvChannelHub <$> ask
        writeChan channel (Private, Event event reply)
    broadcast event reply = do
        channel <- channelHubGlobal . handlerEnvChannelHub <$> ask
        sessionID <- handlerEnvSessionID <$> ask
        writeChan channel (Broadcast sessionID, Event event reply)

instance Publisher CallbackM where
    emit event reply = do
        channel <- CallbackM . lift $ channelHubLocal . callbackEnvChannelHub <$> ask
        writeChan channel (Private, Event event reply)
    broadcast event reply = do
        channel <- CallbackM . lift $ channelHubGlobal . callbackEnvChannelHub <$> ask
        sessionID <- CallbackM . lift $ callbackEnvSessionID <$> ask
        writeChan channel (Broadcast sessionID, Event event reply)

--------------------------------------------------------------------------------
-- | Receiving events.
class Subscriber m where
    -- @
    -- 'on' \"ping\" $ do
    --     'emit' \"pong\" []
    -- @
    on  :: EventName        -- ^ name of event to listen to
        -> CallbackM ()     -- ^ callback
        -> m ()             

instance Subscriber HandlerM where
    on event callback = do
        HandlerM . lift . tell $ [(event, callback)]
  
--------------------------------------------------------------------------------
-- | Now only xhr-polling is supported. <https://github.com/LearnBoost/socket.io-spec#transport-id socket.io-spec#transport-id>
data Transport = WebSocket | XHRPolling | NoTransport deriving (Eq, Show)

instance Serializable Transport where
    serialize WebSocket = "websocket" 
    serialize XHRPolling = "xhr-polling" 
    serialize NoTransport = "unknown" 