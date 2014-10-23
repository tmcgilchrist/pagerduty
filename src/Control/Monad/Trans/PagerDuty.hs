{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE KindSignatures             #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE RecordWildCards            #-}
{-# LANGUAGE TemplateHaskell            #-}
{-# LANGUAGE TypeFamilies               #-}
{-# LANGUAGE UndecidableInstances       #-}

-- Module      : Control.Monad.Trans.PagerDuty
-- Copyright   : (c) 2013-2014 Brendan Hay <brendan.g.hay@gmail.com>
-- License     : This Source Code Form is subject to the terms of
--               the Mozilla Public License, v. 2.0.
--               A copy of the MPL can be found in the LICENSE file or
--               you can obtain it at http://mozilla.org/MPL/2.0/.
-- Maintainer  : Brendan Hay <brendan.g.hay@gmail.com>
-- Stability   : experimental
-- Portability : non-portable (GHC extensions)

module Control.Monad.Trans.PagerDuty
    (
    -- * Transformer
      PagerDuty
    , PagerDutyT

    -- * Run
    , runPagerDutyT

    -- * Environment
    , Env
    , envDomain
    , envAuth
    , envManager
    , envLogger

    -- * Integration API
    , submit

    -- * REST API
    , send
    , paginate
    ) where

import           Control.Applicative
import           Control.Monad.Base
import           Control.Monad.Catch
import           Control.Monad.Except
import           Control.Monad.Morph
import           Control.Monad.Reader
import           Control.Monad.Trans.Control
import           Data.Aeson
import           Data.Conduit
import           Network.PagerDuty.Integration    (Event, Response)
import qualified Network.PagerDuty.Integration    as Int
import           Network.PagerDuty.Internal.Types
import qualified Network.PagerDuty.REST           as REST

-- | A convenient alias for 'PagerDutyT' 'IO'.
type PagerDuty s = PagerDutyT s IO

newtype PagerDutyT s m a = PagerDutyT
    { unPagerDutyT :: ReaderT (Env s) (ExceptT Error m) a
    } deriving
        ( Functor
        , Applicative
        , Monad
        , MonadIO
        , MonadThrow
        , MonadCatch
        , MonadReader (Env s)
        , MonadError  Error
        )

instance MonadTrans (PagerDutyT s) where
    lift = PagerDutyT . lift . lift
    {-# INLINE lift #-}

instance MonadBase b m => MonadBase b (PagerDutyT s m) where
    liftBase = liftBaseDefault
    {-# INLINE liftBase #-}

instance MonadTransControl (PagerDutyT s) where
    newtype StT (PagerDutyT s) a = StTPDT
        { unStT :: StT (ExceptT Error) (StT (ReaderT (Env s)) a)
        }

    liftWith f = PagerDutyT $
        liftWith $ \g ->
            liftWith $ \h ->
                f (liftM StTPDT . h . g . unPagerDutyT)
    {-# INLINE liftWith #-}

    restoreT = PagerDutyT . restoreT . restoreT . liftM unStT
    {-# INLINE restoreT #-}

instance MonadBaseControl b m => MonadBaseControl b (PagerDutyT s m) where
    newtype StM (PagerDutyT s m) a = StMPDT
        { unStMPDT :: ComposeSt (PagerDutyT s) m a
        }

    liftBaseWith = defaultLiftBaseWith StMPDT
    {-# INLINE liftBaseWith #-}

    restoreM = defaultRestoreM unStMPDT
    {-# INLINE restoreM #-}

instance MFunctor (PagerDutyT s) where
    hoist nat m = PagerDutyT (ReaderT (ExceptT . nat . runPagerDutyT m))
    {-# INLINE hoist #-}

instance MMonad (PagerDutyT s) where
    embed f m = ask >>= f . runPagerDutyT m >>= either throwError return
    {-# INLINE embed #-}

runPagerDutyT :: PagerDutyT s m a -> Env s -> m (Either Error a)
runPagerDutyT (PagerDutyT k) = runExceptT . runReaderT k

hoistEither :: (MonadError Error m) => Either Error a -> m a
hoistEither = either throwError return

scoped :: MonadReader (Env s) m => (Env s -> m a) -> m a
scoped f = ask >>= f

submit :: ( MonadIO m
          , MonadReader (Env s) m
          , MonadError Error m
          , Event a
          )
       => a
       -> m Response
submit = submitCatch >=> hoistEither

submitCatch :: ( MonadIO m
               , MonadReader (Env s) m
               , Event a
               )
            => a
            -> m (Either Error Response)
submitCatch x = scoped $ \e -> Int.submitWith (_envManager e) (_envLogger e) x

send :: ( MonadIO m
        , MonadReader (Env s) m
        , MonadError Error m
        , FromJSON b
        )
     => Request a s b
     -> m b
send = sendCatch >=> hoistEither

sendCatch :: ( MonadIO m
             , MonadReader (Env s) m
             , FromJSON b
             )
          => Request a s b
          -> m (Either Error b)
sendCatch x = scoped (`REST.sendWith` x)

paginate :: ( MonadIO m
            , MonadReader (Env s) m
            , MonadError Error m
            , Paginate a
            , FromJSON b
            )
         => Request a s b
         -> Source m b
paginate x = paginateCatch x $= awaitForever (hoistEither >=> yield)

paginateCatch :: ( MonadIO m
                 , MonadReader (Env s) m
                 , Paginate a
                 , FromJSON b
                 )
              => Request a s b
              -> Source m (Either Error b)
paginateCatch x = scoped (`REST.paginateWith` x)
