%% @author Marc Worrell <marc@worrell.nl>
%% @copyright 2020-2026 Driebit BV
%% @doc Payment PSP module for Buckaroo
%% @end

%% Copyright 2020-2026 Driebit BV
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

-module(mod_payment_buckaroo).

-mod_title("Payments using Buckaroo").
-mod_description("Payments using Payment Service Provider Buckaroo").
-mod_author("Driebit").
-mod_depends([ mod_payment ]).
-mod_config([
    #{
        key => is_live,
        type => boolean,
        default => false,
        description => "Use the live Buckaroo checkout environment instead of the test environment."
    },
    #{
        key => website_key,
        type => binary,
        default => <<>>,
        description => "Buckaroo website API key."
    },
    #{
        key => secret_key,
        type => binary,
        default => <<>>,
        description => "Buckaroo secret API key."
    },
    #{
        key => webhook_host,
        type => binary,
        default => <<>>,
        description => "Optional externally reachable webhook host, including protocol, for development or proxy setups."
    },
    #{
        key => invoice_nr_prefix,
        type => binary,
        default => <<"INV">>,
        description => "Prefix for generated Buckaroo invoice numbers."
    },
    #{
        key => services_excluded,
        type => binary,
        default => <<>>,
        description => "Comma separated Buckaroo service codes excluded from the payment form."
    },
    #{
        key => services_selectable,
        type => binary,
        default => <<>>,
        description => "Comma separated Buckaroo service codes selectable on the payment form."
    }
]).

-author("Driebit <tech@driebit.nl>").

-export([
    observe_payment_psp_request/2,
    observe_payment_psp_view_url/2,
    observe_payment_psp_status_sync/2
]).

-include_lib("kernel/include/logger.hrl").
-include_lib("zotonic_mod_payment/include/payment.hrl").

%% @doc Payment request, make new payment with Buckaroo, return
%%      payment (buckaroo) details and a redirect uri for the user
%%      to handle the payment.
observe_payment_psp_request(#payment_psp_request{ payment_id = PaymentId, currency = <<"EUR">> }, Context) ->
    m_payment_buckaroo_api:create(PaymentId, Context);
observe_payment_psp_request(#payment_psp_request{}, _Context) ->
    undefined.

observe_payment_psp_view_url(#payment_psp_view_url{ psp_module = ?MODULE, psp_external_id = BuckarooId }, _Context) ->
    {ok, m_payment_buckaroo_api:payment_url(BuckarooId)};
observe_payment_psp_view_url(#payment_psp_view_url{}, _Context) ->
    undefined.


observe_payment_psp_status_sync(#payment_psp_status_sync{
        payment_id = PaymentId,
        psp_module = ?MODULE,
        psp_external_id = BuckarooId
    }, Context) ->
    case m_payment_buckaroo_api:transaction_status(BuckarooId, Context) of
        {ok, {Code, DT}} ->
            m_payment_buckaroo_api:update_payment_status(PaymentId, Code, DT, Context),
            ok;
        {error, 404} = Error ->
            ?LOG_WARNING(#{
                in => zotonic_mod_payment_buckaroo,
                text => <<"Buckaroo status sync: unknown payment id">>,
                result => error,
                reason => notfound,
                payment_id => PaymentId
            }),
            Error;
        {error, _} = Error ->
            Error
    end;
observe_payment_psp_status_sync(#payment_psp_status_sync{}, _Context) ->
    undefined.
