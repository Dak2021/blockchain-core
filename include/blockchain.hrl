% Protocols
-define(GOSSIP_PROTOCOL_V1, "blockchain_gossip/1.0.0").
-define(SYNC_PROTOCOL_V1, "blockchain_sync/1.1.0").
-define(FASTFORWARD_PROTOCOL_V1, "blockchain_fastforward/1.0.0").

-define(SYNC_PROTOCOL_V2, "blockchain_sync/1.2.0").
-define(FASTFORWARD_PROTOCOL_V2, "blockchain_fastforward/1.2.0").

-define(TX_PROTOCOL_V1, "blockchain_txn/1.0.0").
-define(TX_PROTOCOL_V2, "blockchain_txn/2.0.0").

-define(SUPPORTED_GOSSIP_PROTOCOLS, [?GOSSIP_PROTOCOL_V1]).
-define(SUPPORTED_SYNC_PROTOCOLS, [?SYNC_PROTOCOL_V2, ?SYNC_PROTOCOL_V1]).
-define(SUPPORTED_FASTFORWARD_PROTOCOLS, [?FASTFORWARD_PROTOCOL_V2, ?FASTFORWARD_PROTOCOL_V1]).
-define(SUPPORTED_TX_PROTOCOLS, [?TX_PROTOCOL_V2, ?TX_PROTOCOL_V1]).

-define(SNAPSHOT_PROTOCOL, "blockchain_snapshot/1.0.0").

-define(LOC_ASSERTION_PROTOCOL, "loc_assertion/1.0.0").
-define(STATE_CHANNEL_PROTOCOL_V1, "state_channel/1.0.0").

% B58 Address Versions
-define(B58_MAINNET_VER, 0).
-define(B58_TESTNET_VER, 2).
-define(B58_HTLC_VER, 24).

% Misc
-define(EVT_MGR, blockchain_event_mgr).
-define(POC_EVT_MGR, blockchain_poc_event_mgr).

-define(BC_UPGRADE_NAMES, [
    <<"gateway_v2">>,
    <<"hex_targets">>,
    <<"gateway_oui">>,
    <<"h3dex">>,
    <<"h3dex2">>,
    <<"gateway_lg3">>,
    <<"clear_witnesses">>,
    <<"clear_scores">>,
    <<"clear_scores2">>,
    <<"nonce_rescue">>,
    <<"poc_upgrade">>
]).

-define(bones(HNT), HNT * 100000000).

-record(block_info,
        {
         time :: non_neg_integer(),
         height :: non_neg_integer(),
         hash :: blockchain_block:hash(),
         pocs :: map()
        }).
-record(block_info_v2,
        {
         time :: non_neg_integer(),
         height :: non_neg_integer(),
         hash :: blockchain_block:hash(),
         pocs :: blockchain_block_v1:poc_keys() | map(),
         hbbft_round :: non_neg_integer(),
         election_info :: {non_neg_integer(), non_neg_integer()},
         penalties :: {binary(), [{pos_integer(), binary()}]}
        }).

-record(blockchain, {
    dir :: file:filename_all(),
    db :: rocksdb:db_handle(),
    default :: rocksdb:cf_handle(),
    blocks :: rocksdb:cf_handle(),
    heights :: rocksdb:cf_handle(),
    info :: rocksdb:cf_handle(),
    temp_blocks :: rocksdb:cf_handle(),
    plausible_blocks :: rocksdb:cf_handle(),
    snapshots :: rocksdb:cf_handle(),
    implicit_burns :: rocksdb:cf_handle(),
    htlc_receipts :: rocksdb:cf_handle(),
    ledger :: blockchain_ledger_v1:ledger()
}).
