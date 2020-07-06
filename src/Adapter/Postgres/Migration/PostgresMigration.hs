module Adapter.Postgres.Migration.PostgresMigration where

import Control.Exception
import Control.Monad.IO.Class (MonadIO, liftIO)
import Control.Monad.Catch
import Data.Pool
import Data.Typeable
import qualified Database.PostgreSQL.Simple as PG
import qualified Database.PostgreSQL.Simple.Migration as M

migrate :: (MonadIO m, MonadThrow m) => Pool PG.Connection -> String -> m ()
migrate pool dir = do
  migration <- liftIO $ withResource pool
    (\conn -> PG.withTransaction conn (M.runMigrations False conn commands))
  case migration of
    M.MigrationError e -> throwM MigrationException
    _                  -> return ()
  where
    commands = [M.MigrationInitialization, M.MigrationValidation (M.MigrationDirectory dir)]
    
data MigrationException = MigrationException deriving (Show, Typeable)

instance Exception MigrationException