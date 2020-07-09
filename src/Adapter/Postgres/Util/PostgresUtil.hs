{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE BlockArguments #-}
module Adapter.Postgres.Util.PostgresUtil (PostgresUtil(..), PostgresException(..)) where

import Adapter.Katip.Logger
import Control.Exception (Exception, catch)
import Control.Monad.Catch (MonadThrow, throwM)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Pool
import Data.Typeable
import qualified Database.PostgreSQL.Simple as PG
import Database.PostgreSQL.Simple.FromRow
import Database.PostgreSQL.Simple.ToRow
import Katip
import Data.Int (Int64)

class PostgresUtil m where
  queryOne :: (FromRow a, ToRow b) => Pool PG.Connection
    -> PG.Query -> b -> m (Maybe a)
  queryListWithoutParams :: FromRow a => Pool PG.Connection
    -> PG.Query -> m [a]
  queryList :: (FromRow a, ToRow b) => Pool PG.Connection
    -> PG.Query -> b -> m [a]
  command :: ToRow b => Pool PG.Connection -> PG.Query
    -> b -> m (Bool)

instance PostgresUtil IO where
  queryOne pool q b = queryOne' pool q b
  queryListWithoutParams pool q = queryListWithoutParams' pool q
  queryList pool q b = queryList' pool q b
  command pool c b = command' pool c b 

queryOne' :: (MonadIO m, MonadThrow m, FromRow a, ToRow b)
  => Pool PG.Connection
  -> PG.Query -> b -> m (Maybe a)
queryOne' p' q' b = do
  liftIO $ logger $ \logEnv -> do
    runKatipContextT logEnv () namespace $ do
      $(logTM) InfoS $ "Query One Start..."
  result <- liftIO $ withResource p' (\conn -> PG.query conn q' b)
    `catch` \e -> handleSqlError e namespace
  liftIO $ logger $ \logEnv -> do
    runKatipContextT logEnv () namespace $ do
      $(logTM) InfoS $ "Query One End..."
  case result of
        (h: _) -> return $ Just h
        _      -> return Nothing
  where
    namespace = "query-one"

queryList' :: (MonadIO m, MonadThrow m, FromRow a, ToRow b)
  => Pool PG.Connection
  -> PG.Query -> b -> m [a]
queryList' p' q' b = do
  liftIO $ logger $ \logEnv -> do
    runKatipContextT logEnv () namespace $ do
      $(logTM) InfoS $ "Query List Start..."
  result <- liftIO $ withResource p' (\conn -> PG.query conn q' b)
    `catch` \e -> handleSqlError e namespace
  liftIO $ logger $ \logEnv -> do
    runKatipContextT logEnv () namespace $ do
      $(logTM) InfoS $ "Query List End..."
  return result
  where
    namespace = "query-list"

queryListWithoutParams' :: (MonadIO m, MonadThrow m, FromRow a)
  => Pool PG.Connection
  -> PG.Query -> m [a]
queryListWithoutParams' p' q' = do
  liftIO $ logger $ \logEnv -> do
    runKatipContextT logEnv () namespace $ do
      $(logTM) InfoS $ "Query List Without Params Start..."
  result <- liftIO $ withResource p' (`PG.query_` q') 
    `catch` \e -> handleSqlError e namespace
  liftIO $ logger $ \logEnv -> do
    runKatipContextT logEnv () namespace $ do
      $(logTM) InfoS $ "Query List Without Params End..."
  return result
  where
    namespace = "query-list-without-params"

command' :: (MonadIO m, MonadThrow m, ToRow b)
  => Pool PG.Connection
  -> PG.Query -> b -> m Bool
command' p' q' b = do
  liftIO $ logger $ \logEnv -> do
    runKatipContextT logEnv () namespace $ do
      $(logTM) InfoS $ "Command Start..."
  result <- liftIO $ withResource p' (\conn -> PG.execute conn q' b)
    `catch` \e -> handleSqlError e namespace
  liftIO $ logger $ \logEnv -> do
    runKatipContextT logEnv () namespace $ do
      $(logTM) InfoS $ "Command End..."
  return (result > 0)
  where
    namespace = "command"

newtype PostgresException = PostgresException String deriving (Show, Typeable)

instance Exception PostgresException

handleSqlError :: (MonadIO m, MonadThrow m) => PG.SqlError -> Namespace -> m a
handleSqlError e @ (PG.SqlError _ _ m _ _) namespace = do
  liftIO $ logger $ \logEnv -> do
    runKatipContextT logEnv () namespace $ do
      $(logTM) ErrorS $ "Error..."
  throwM $ PostgresException (show e)