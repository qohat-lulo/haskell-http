{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE OverloadedStrings #-}

module Adapter.Postgres.Products (ProductRepository (..)) where

import qualified Adapter.Effect.AsyncTask as ASYNC
import qualified Adapter.Postgres.Util.Postgres as UTIL
import Control.Exception (catch)
import Control.Monad.Catch (MonadThrow, throwM)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Pool (Pool)
import Data.Text (Text)
import Data.Time (ZonedTime)
import qualified Database.PostgreSQL.Simple as PG
import Database.PostgreSQL.Simple.FromRow (FromRow (..), field)
import Database.PostgreSQL.Simple.ToField (toField)
import Database.PostgreSQL.Simple.ToRow (ToRow (..))
import qualified Domain.Products as DOMAIN

class (Monad m, Functor m) => ProductRepository m c where
  findById :: c -> Text -> m (Maybe DOMAIN.Product)
  findAll :: c -> m [DOMAIN.Product]
  create :: c -> DOMAIN.Product -> m Bool
  deleteById :: c -> Text -> m Bool
  update :: c -> Text -> Text -> Double -> m Bool

instance ProductRepository IO (Pool PG.Connection) where
  findById pool id' = do
    result <- ASYNC.run $ findById' pool id'
    case result of
      Just value -> return $ Just (to value)
      Nothing -> return Nothing
  findAll pool = ASYNC.run $ fmap (map to) (findAll' pool)
  create pool product' = ASYNC.run $ create' pool product'
  deleteById pool id' = deleteById' pool id'
  update pool id' name stock = update' pool id' name stock

data ProductRow = ProductRow
  { _id :: Text,
    _name :: Text,
    _stock :: Double,
    _create_at :: ZonedTime
  }

instance FromRow ProductRow where
  fromRow = ProductRow <$> field <*> field <*> field <*> field

instance ToRow ProductRow where
  toRow p =
    [ toField (_id p),
      toField (_name p),
      toField (_stock p),
      toField (_create_at p)
    ]

findById' ::
  MonadIO m =>
  Pool PG.Connection ->
  Text ->
  m (Maybe ProductRow)
findById' pool' id' =
  liftIO $
    UTIL.queryOne pool' sql [id' :: Text] -- or (PG.Only (id' :: Text))
      `catch` handlePgException
  where
    sql =
      "SELECT * FROM products\n\
      \WHERE id = ?"

findAll' ::
  MonadIO m =>
  Pool PG.Connection ->
  m [ProductRow]
findAll' pool' =
  liftIO $
    UTIL.queryListWithoutParams pool' sql
      `catch` handlePgException
  where
    sql = "SELECT * FROM products"

create' ::
  MonadIO m =>
  Pool PG.Connection ->
  DOMAIN.Product ->
  m Bool
create' pool' product' = do
  let row = from product'
  liftIO $
    UTIL.command pool' sql (_id row, _name row, _stock row, _create_at row)
      `catch` handlePgException
  where
    sql =
      "INSERT INTO products (id, name, stock, created_at)\n\
      \VALUES (?, ?, ?, ?)"

deleteById' ::
  MonadIO m =>
  Pool PG.Connection ->
  Text ->
  m Bool
deleteById' pool' id' = do
  liftIO $
    UTIL.command pool' sql (PG.Only (id' :: Text))
      `catch` handlePgException
  where
    sql =
      "DELETE FROM products\n\
      \WHERE id = ?"

update' ::
  MonadIO m =>
  Pool PG.Connection ->
  Text ->
  Text ->
  Double ->
  m Bool
update' pool' id' name' stock' = do
  liftIO $
    UTIL.command pool' sql (name' :: Text, stock' :: Double, id' :: Text)
      `catch` handlePgException
  where
    sql =
      "UPDATE products\n\
      \SET name = ?, stock = ?\n\
      \WHERE id = ?"

handlePgException :: MonadThrow m => UTIL.PostgresException -> m a
handlePgException (UTIL.PostgresException em) = throwM $ DOMAIN.ProductException em

to :: ProductRow -> DOMAIN.Product
to row =
  DOMAIN.Product
    { DOMAIN.productId = DOMAIN.ProductId (_id row),
      DOMAIN.productName = DOMAIN.ProductName (_name row),
      DOMAIN.productStock = DOMAIN.ProductStock (_stock row),
      DOMAIN.productCreatedAt = DOMAIN.ProductCreatedAt (_create_at row)
    }

from :: DOMAIN.Product -> ProductRow
from p =
  ProductRow
    { _id = DOMAIN.id (DOMAIN.productId p),
      _name = DOMAIN.name (DOMAIN.productName p),
      _stock = DOMAIN.stock (DOMAIN.productStock p),
      _create_at = DOMAIN.createdAt (DOMAIN.productCreatedAt p)
    }
