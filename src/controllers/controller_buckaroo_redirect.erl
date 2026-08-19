%% @copyright 2020-2026 Driebit BV
%% @doc Buckaroo redirect the user with a POST to this controller
%%      after a payment has been done at their HTML gateway.
%%      This controller processes the payment status and then redirects
%%      to either the payment_psp_done or payment_psp_cancel page.
%% @end

%% Copyright 2012-2026 Marc Worrrell
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

% Fields are documented here: https://support.buckaroo.nl/categorieën/transacties/push-berichten
%
% Sample post:
%
% #{
%   <<"payment_nr">> => <<"zozqioczidkgfdvlrxvrjrshrzxbuzkm">>,
%   <<"z_language">> => <<"nl">>,
%   <<"brq_amount">> => <<"1.00">>,
%   <<"brq_currency">> => <<"EUR">>,
%   <<"brq_customer_name">> => <<"J. de Täster"/utf8>>,
%   <<"brq_description">> => <<"Test">>,
%   <<"brq_invoicenumber">> => <<"INV0000.0000.0008">>,
%   <<"brq_payer_hash">> =>
%       <<"1892294f6d278d65ec5425896418d6ae62146741f03393654959febe6e73d5c822c461c521761c3732b4f96dc7a7fc57eba7aac0a736fb948861ce2081c79fba">>,
%   <<"brq_payment">> => <<"8586EFA60B5A41E29B4CF002227CC68F">>,
%   <<"brq_payment_method">> => <<"ideal">>,
%   <<"brq_SERVICE_ideal_consumerBIC">> => <<"RABONL2U">>,
%   <<"brq_SERVICE_ideal_consumerIBAN">> => <<"NL44RABO0123456789">>,
%   <<"brq_SERVICE_ideal_consumerIssuer">> => <<"Handelsbanken">>,
%   <<"brq_SERVICE_ideal_consumerName">> => <<"J. de Täster"/utf8>>,
%   <<"brq_SERVICE_ideal_transactionId">> => <<"0000000000000001">>,
%   <<"brq_statuscode">> => <<"190">>,
%   <<"brq_statuscode_detail">> => <<"S001">>,
%   <<"brq_statusmessage">> => <<"Transaction successfully processed">>,
%   <<"brq_test">> => <<"true">>,
%   <<"brq_timestamp">> => <<"2020-04-30 17:56:49">>,
%   <<"brq_transactions">> => <<"0280343636F047079E523F1EE71959BD">>,
%   <<"brq_websitekey">> => <<"CQxkFU644M">>,
%   <<"brq_signature">> => <<"3d8f2ab0039e94eb9901dc80d44207f921abd1a3">>
% }

-module(controller_buckaroo_redirect).

-export([
    allowed_methods/1,
    resource_exists/1,
    previously_existed/1,
    moved_temporarily/1
    ]).

-include_lib("kernel/include/logger.hrl").

-type sign_arg() :: {binary(), binary(), binary()}.
-type redirect_response() :: {{true, binary() | string()}, z:context()}.

-spec allowed_methods(Context) -> {Methods, Context}
    when
        Context :: z:context(),
        Methods :: [ binary() ].
allowed_methods(Context) ->
    {[ <<"POST">> ], Context}.

-spec resource_exists(Context) -> {false, Context}
    when
        Context :: z:context().
resource_exists(Context) ->
    {false, Context}.

-spec previously_existed(Context) -> {true, Context}
    when
        Context :: z:context().
previously_existed(Context) ->
    {true, Context}.

-spec moved_temporarily(Context) -> Result
    when
        Context :: z:context(),
        Result :: redirect_response().
moved_temporarily(Context) ->
    Context1 = z_context:ensure_qs(Context),
    case is_signature_ok(Context1) of
        false ->
            redirect(Context1);
        true ->
            StatusCode = z_convert:to_integer(z_context:get_q(<<"brq_statuscode">>, Context1)),
            Timestamp = z_context:get_q(<<"brq_timestamp">>, Context1),
            PspId = z_context:get_q(<<"brq_transactions">>, Context1),
            case set_status(PspId, StatusCode, Timestamp, Context1) of
                ok ->
                    ?LOG_INFO(#{
                        in => zotonic_mod_payment_buckaroo,
                        text => <<"Buckaroo redirect: payment status updated">>,
                        result => ok,
                        psp_external_id => PspId,
                        status => StatusCode,
                        timestamp => Timestamp
                    });
                {error, Reason} ->
                    ?LOG_ERROR(#{
                        in => zotonic_mod_payment_buckaroo,
                        text => <<"Buckaroo redirect: failed to update payment status">>,
                        result => error,
                        reason => Reason,
                        psp_external_id => PspId,
                        status => StatusCode,
                        timestamp => Timestamp
                    })
            end,
            redirect(Context1)
    end.

-spec set_status(PspId, StatusCode, Timestamp, Context) -> Result
    when
        PspId :: binary() | undefined,
        StatusCode :: integer(),
        Timestamp :: binary() | undefined,
        Context :: z:context(),
        Result :: ok | {error, term()}.
set_status(PspId, StatusCode, Timestamp, Context) ->
    case m_payment:get_by_psp(mod_payment_buckaroo, PspId, Context) of
        {ok, Payment} ->
            Id = maps:get(<<"id">>, Payment),
            % The posted timestamp seems to be in the local time of Buckaroo?
            % As this timestamp is unsure we have to assume it should be in the
            % range [-10min ... -10sec], as it is a semi-real-time event.
            % We err on the safe side of being a bit too early so that future events
            % are accepted as being after this event.
            Now = calendar:universal_time(),
            Now_10m = prev_min(10, Now),
            Now_10s = prev_sec(10, Now),
            TimestampDT = z_datetime:to_datetime(Timestamp, <<"Europe/Berlin">>),
            DateTime = erlang:max(Now_10m, erlang:min(Now_10s, TimestampDT)),
            _ = m_payment_buckaroo_api:maybe_update_contact(
                Id,
                PspId,
                payment_link_contact(Context),
                maps:get(<<"status">>, Payment),
                StatusCode,
                Context),
            m_payment_buckaroo_api:update_payment_status(Id, StatusCode, DateTime, Context);
        {error, _} = Error ->
            Error
    end.

payment_link_contact(Context) ->
    buckaroo_name_props(
        first_defined([
            z_context:get_q(<<"brq_customer_name">>, Context),
            z_context:get_q(<<"brq_SERVICE_ideal_consumerName">>, Context)
        ])).

buckaroo_name_props(Name) when is_binary(Name) ->
    case binary:split(z_string:trim(Name), <<" ">>, [global, trim_all]) of
        [] ->
            #{};
        [<<>>] ->
            #{};
        [Surname] ->
            #{ <<"name_surname">> => Surname };
        [First | Rest] ->
            #{ <<"name_first">> => First,
               <<"name_surname">> => iolist_to_binary(lists:join(<<" ">>, Rest)) }
    end;
buckaroo_name_props(_) ->
    #{}.

first_defined([Value | Rest]) ->
    case z_utils:is_empty(Value) of
        true -> first_defined(Rest);
        false -> Value
    end;
first_defined([]) ->
    undefined.

-spec prev_min(N, DateTime) -> DateTime
    when
        N :: non_neg_integer(),
        DateTime :: calendar:datetime().
prev_min(0, DT) -> DT;
prev_min(N, DT) when N > 0 -> prev_min(N-1, z_datetime:prev_minute(DT)).

-spec prev_sec(N, DateTime) -> DateTime
    when
        N :: non_neg_integer(),
        DateTime :: calendar:datetime().
prev_sec(0, DT) -> DT;
prev_sec(N, DT) when N > 0 -> prev_sec(N-1, z_datetime:prev_second(DT)).

-spec redirect(Context) -> Result
    when
        Context :: z:context(),
        Result :: redirect_response().
redirect(Context) ->
    Args = [
        {payment_nr, z_context:get_q(<<"payment_nr">>, Context)}
    ],
    Location = z_context:abs_url(
        z_dispatcher:url_for(payment_psp_done, Args, none, Context),
        Context),
    {{true, Location}, Context}.


-spec is_signature_ok(Context) -> IsOk
    when
        Context :: z:context(),
        IsOk :: boolean().
is_signature_ok(Context) ->
    Args = [
            {
                z_string:to_lower(K),
                K,
                V
            }
            || {K,V} <- z_context:get_q_all_noz(Context), is_binary(V)
           ],
    Args1 = lists:filter(fun is_brq_sign_arg/1, Args),
    SigString = sig_string(Args1),
    OurSig = sig(SigString, Context),
    SigQ = q_sig(Args),
    case OurSig of
        SigQ ->
            true;
        _Other ->
            ?LOG_ERROR(#{
                in => zotonic_mod_payment_buckaroo,
                text => <<"Buckaroo redirect: signature mismatch">>,
                result => error,
                reason => signature_mismatch,
                signature => SigQ,
                expected => OurSig,
                args => Args1
            }),
            false
    end.

-spec is_brq_sign_arg(Arg) -> IsSignArg
    when
        Arg :: sign_arg(),
        IsSignArg :: boolean().
is_brq_sign_arg({<<"brq_signature">>, _, _}) -> false;
is_brq_sign_arg({<<"brq_", _/binary>>, _, _}) -> true;
is_brq_sign_arg({<<"cust_", _/binary>>, _, _}) -> true;
is_brq_sign_arg({<<"add_", _/binary>>, _, _}) -> true;
is_brq_sign_arg(_) -> false.

-spec q_sig(Args) -> Signature
    when
        Args :: [ sign_arg() ],
        Signature :: binary().
q_sig(Args) ->
    case lists:keyfind(<<"brq_signature">>, 1, Args) of
        {<<"brq_signature">>, _, Sig} ->
            z_string:to_lower(Sig);
        false ->
            <<>>
    end.

-spec sig_string(Args) -> SignatureString
    when
        Args :: [ sign_arg() ],
        SignatureString :: binary().
sig_string(Qs) ->
    Qs1 = lists:sort(Qs),
    iolist_to_binary([ [
            K,
            $=,
            V
        ] || {_, K,V} <- Qs1 ]).

-spec sig(SignatureString, Context) -> Signature
    when
        SignatureString :: iodata(),
        Context :: z:context(),
        Signature :: binary().
sig(SigString, Context) ->
    Data = [
        SigString,
        z_convert:to_binary(m_config:get_value(mod_payment_buckaroo, secret_key, Context))
    ],
    Sha = crypto:hash(sha, Data),
    z_string:to_lower(iolist_to_binary(z_url:hex_encode(Sha))).
