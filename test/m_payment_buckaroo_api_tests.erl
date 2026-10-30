%% @copyright 2026 Driebit BV
%% @doc Tests for Buckaroo payment normalization.
%% @end

%% Copyright 2026 Driebit BV
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

-module(m_payment_buckaroo_api_tests).
-include_lib("eunit/include/eunit.hrl").

external_push_test() ->
    T = #{<<"Key">> => <<"external-key">>, <<"Invoice">> => <<"someone-elses-reference">>,
          <<"AmountDebit">> => 12.34, <<"Currency">> => <<"EUR">>,
          <<"Consumer">> => null, <<"Customer">> => null,
          <<"Status">> => #{<<"Code">> => #{<<"Code">> => 190},
                            <<"DateTime">> => <<"2026-10-29T10:00:00">>}},
    {ok, D} = m_payment_buckaroo_api:webhook_payment(#{<<"Transaction">> => T}),
    ?assertEqual(<<"external-key">>, maps:get(psp_external_id, D)),
    ?assertEqual(paid, maps:get(status, D)),
    ?assertEqual(12.34, maps:get(amount, D)),
    ?assertEqual({error, credit_transaction}, m_payment_buckaroo_api:webhook_payment(
        #{<<"Transaction">> => T#{<<"AmountCredit">> => 12.34}})),
    ?assertEqual({error, payload}, m_payment_buckaroo_api:webhook_payment(#{})).
