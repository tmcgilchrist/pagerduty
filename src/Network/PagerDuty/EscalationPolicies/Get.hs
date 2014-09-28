{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell   #-}

-- Module      : Network.PagerDuty.EscalationPolicies.Get
-- Copyright   : (c) 2013-2014 Brendan Hay <brendan.g.hay@gmail.com>
-- License     : This Source Code Form is subject to the terms of
--               the Mozilla Public License, v. 2.0.
--               A copy of the MPL can be found in the LICENSE file or
--               you can obtain it at http://mozilla.org/MPL/2.0/.
-- Maintainer  : Brendan Hay <brendan.g.hay@gmail.com>
-- Stability   : experimental
-- Portability : non-portable (GHC extensions)

-- | Get information about an existing escalation policy and its rules.
--
-- @GET \/escalation_policies\/\:id@
--
-- See: <http://developer.pagerduty.com/documentation/rest/escalation_policies/show>
module Network.PagerDuty.EscalationPolicies.Get
    ( getPolicy
    ) where

import Data.Aeson.Lens
import Network.HTTP.Types
import Network.PagerDuty.EscalationPolicies.Types
import Network.PagerDuty.TH
import Network.PagerDuty.Types

data GetPolicy = GetPolicy

deriveJSON ''GetPolicy

getPolicy :: PolicyId -> Request GetPolicy Token Policy
getPolicy i = req GET i (key "escalation_policy") GetPolicy