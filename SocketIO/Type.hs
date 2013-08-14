{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module SocketIO.Type where


import Network.HTTP.Types (Method)

import qualified Data.HashTable.IO as H
import qualified Data.Text.Lazy as TL
import Data.IORef
import Data.Aeson
import Data.Monoid ((<>))
import GHC.Generics
import Control.Monad.Reader       


--

type Text = TL.Text
type Event = Text
type Reply = Text
type Namespace = Text
type Protocol = Text
type Transport = Text
type SessionID = Text 

type HashTable k v = H.LinearHashTable k v
data Status = Connecting | Connected | Disconnecting | Disconnected deriving Show
type Session = (SessionID, Status)
type Table = HashTable SessionID Status 
data SocketRequest = SocketRequest Method Namespace Protocol Transport SessionID deriving (Show)

data Connection = Handshake | Connection SessionID | Disconnection deriving Show 

newtype SessionRefM b a = SessionRefM { runSessionM :: (ReaderT (IORef b) IO) a }
    deriving (Monad, Functor, MonadIO, MonadReader (IORef b))

type SessionM a = SessionRefM Table a

data Message    = MsgDisconnect Endpoint
                | MsgConnect Endpoint
                | MsgHeartbeat
                | Msg ID Endpoint Data
                | MsgJSON ID Endpoint Data
                | MsgEvent ID Endpoint Data
                | MsgACK ID Data
                | MsgError Endpoint Data
                | MsgNoop
                deriving (Show, Eq)

data Endpoint   = Endpoint String
                | NoEndpoint
                deriving (Show, Eq)
data ID         = ID Int
                | IDPlus Int
                | NoID
                deriving (Show, Eq)
data Data       = Data Text
                | EventData Trigger
                | NoData
                deriving (Show, Eq)

data Trigger    = Trigger { name :: Event, args :: Reply } deriving (Show, Eq, Generic)

instance FromJSON Trigger

class Msg m where
    toMessage :: m -> Text

instance Msg Endpoint where
    toMessage (Endpoint s) = TL.pack s
    toMessage NoEndpoint = ""

instance Msg ID where
    toMessage (ID i) = TL.pack $ show i
    toMessage (IDPlus i) = TL.pack $ show i ++ "+"
    toMessage NoID = ""

instance Msg Data where
    toMessage (Data s) = s
    toMessage NoData = ""

instance Msg Message where
    toMessage (MsgDisconnect NoEndpoint)    = "0"
    toMessage (MsgDisconnect e)             = "0::" <> toMessage e
    toMessage (MsgConnect e)                = "1::" <> toMessage e
    toMessage MsgHeartbeat                  = undefined
    toMessage (Msg i e d)                   = "3:" <> toMessage i <>
                                              ":" <> toMessage e <>
                                              ":" <> toMessage d
    toMessage (MsgJSON i e d)               = "4:" <> toMessage i <>
                                              ":" <> toMessage e <>
                                              ":" <> toMessage d
    toMessage (MsgEvent i e d)              = "5:" <> toMessage i <>
                                              ":" <> toMessage e <>
                                              ":" <> toMessage d
    toMessage (MsgACK i d)                  = "6:::" <> toMessage i <> 
                                              "+" <> toMessage d
    toMessage (MsgError e d)                = "7::" <> toMessage e <> 
                                              ":" <> toMessage d
    toMessage MsgNoop                       = "8:::"