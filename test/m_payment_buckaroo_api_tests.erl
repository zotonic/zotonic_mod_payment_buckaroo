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
