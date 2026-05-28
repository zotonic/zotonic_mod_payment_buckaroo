%% @copyright 2020-2026 Driebit BV
%% @doc Handle push messages from Buckaroo, called if the state
%% of a transaction changes.
%% The Buckaroo HTML gateway calls this synchronously after a
%% payment has been made, before the redirect with as POST to
%% the controller_buckaroo_redirect controller.
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

-module(controller_buckaroo_webhook).

-export([
    allowed_methods/1,
    content_types_accepted/1,
    is_authorized/1,
    process/4
]).

-include_lib("kernel/include/logger.hrl").

-type content_type() :: {binary(), binary(), list()}.
-type service_response() :: {true, z:context()} | {{halt, pos_integer()}, z:context()}.

-spec allowed_methods(Context) -> {Methods, Context}
    when
        Context :: z:context(),
        Methods :: [ binary() ].
allowed_methods(Context) ->
    {[ <<"POST">> ], Context}.

-spec content_types_accepted(Context) -> {ContentTypes, Context}
    when
        Context :: z:context(),
        ContentTypes :: [ content_type() ].
content_types_accepted(Context) ->
    {[ {<<"application">>, <<"json">>, []} ], Context}.

-spec is_authorized(Context) -> Result
    when
        Context :: z:context(),
        Result :: {true, z:context()} | {binary(), z:context()}.
is_authorized(Context) ->
    {Body, Context1} = cowmachine_req:req_body(Context),
    case m_payment_buckaroo_api:is_valid_authorization_header(Body, Context1) of
        true ->
            {true, z_context:set(<<"body">>, Body, Context1)};
        false ->
            ?LOG_ERROR(#{
                in => zotonic_mod_payment_buckaroo,
                text => <<"Buckaroo webhook: invalid authorization">>,
                result => error,
                reason => invalid_authorization
            }),
            {<<"Buckaroo-Authorization">>, Context1}
    end.

-spec process(Method, AcceptedCT, ProvidedCT, Context) -> Result
    when
        Method :: binary(),
        AcceptedCT :: content_type(),
        ProvidedCT :: term(),
        Context :: z:context(),
        Result :: service_response().
process(<<"POST">>, AcceptedCT, _ProvidedCT, Context) ->
    try
        {Decoded, Context1} = z_controller_helper:decode_request_noz(AcceptedCT, Context),
        JSON = case Decoded of
            #{ <<"Transaction">> := _ } = M -> M;
            _ -> z_json:decode(z_context:get(<<"body">>, Context1))
        end,
        case m_payment_buckaroo_api:webhook_data(JSON, Context1) of
            ok ->
                {true, Context1};
            {error, notfound} ->
                {true, Context1};
            {error, _} ->
                {{halt, 500}, Context1}
        end
    catch
        Type:Err:Stack ->
            ?LOG_ERROR(#{
                in => zotonic_mod_payment_buckaroo,
                text => <<"Buckaroo webhook: crash handling request">>,
                result => error,
                reason => Err,
                crash => Type,
                stack => Stack
            }),
            {{halt, 500}, Context}
    end.
