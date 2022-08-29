import 'dart:convert';

import 'package:another_flushbar/flushbar.dart';
import 'package:biometric_storage/biometric_storage.dart';
import 'package:dart_client/api/transactions/models/broadcast_transactions_request.dart';
import 'package:dart_client/client.dart';
import 'package:dart_crypto/identities/address.dart';
import 'package:dart_crypto/identities/public_key.dart';
import 'package:dart_crypto/networks/mainnet.dart';
import 'package:dart_crypto/transactions/types/vote.dart';
import 'package:flutter/material.dart';
import 'package:solar_wallet/wallet_ui_model.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final TextEditingController _labelController = TextEditingController();
  final TextEditingController _passphraseController = TextEditingController();
  final TextEditingController _vote1Controller = TextEditingController();
  final TextEditingController _percentController = TextEditingController();
  final TextEditingController _vote2Controller = TextEditingController();
  final Client _client =
      Client(baseUrl: "https://sxp.mainnet.sh", isDevelopment: true);

  // Map<String, String> _passphrases = {};
  List<WalletUIModel> _wallets = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkAuthenticate();
  }

  @override
  void didChangeDependencies() async {
    super.didChangeDependencies();
    final passphrases = await _loadPassphrases();
    _loadContent(passphrases);
  }

  Future<Map<String, String>> _loadPassphrases() async {
    final store = await BiometricStorage().getStorage('storage');
    final storeContent = await store.read();
    if (storeContent != null) {
      return (jsonDecode(storeContent) as Map<String, dynamic>)
          .map((key, value) => MapEntry(key, value as String));
    }
    return {};
  }

  Future<CanAuthenticateResponse> _checkAuthenticate() async {
    final response = await BiometricStorage().canAuthenticate();
    return response;
  }

  Future<void> _loadContent(Map<String, String> passphrases) async {
    setState(() {
      _isLoading = true;
    });
    final List<WalletUIModel> wallets = [];
    final sortedKeys = passphrases.keys.toList();
    sortedKeys.sort();
    for (final key in sortedKeys) {
      final walletResponse = await _client.wallets.getWallet(
        walletAddress: Address.fromPassphrase(
          passphrases[key]!,
          networkVersion: Mainnet().version(),
        ),
      );
      if (walletResponse.error != null) {
        showBanner(context, Colors.red, jsonEncode(walletResponse.error));
      }
      final wallet = walletResponse.data;
      if (wallet != null) {
        final values = wallet.votingFor?.values;
        double percentage = 0;
        if (values?.isNotEmpty == true) {
          percentage = values!.first.percent;
        }
        wallets.add(
          WalletUIModel(
            label: key,
            address: wallet.address,
            votingFor: wallet.votingFor?.keys.join(",") ?? "",
            percentage: percentage,
            balance: wallet.balance,
          ),
        );
      }
    }
    setState(() {
      _wallets = wallets;
      _isLoading = false;
    });
  }

  void _addPassphraseClicked() async {
    String label = _labelController.text;
    String passphrase = _passphraseController.text;
    _labelController.clear();
    _passphraseController.clear();
    final Map<String, String> newPassphrases = await _loadPassphrases();
    newPassphrases[label] = passphrase;
    final store = await BiometricStorage().getStorage('storage');
    await store.write(jsonEncode(newPassphrases));
    _loadContent(newPassphrases);
  }

  Future<dynamic> _onWalletClicked(
      BuildContext context, WalletUIModel walletUIModel) async {
    return showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Vote for:'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _vote1Controller,
                  decoration:
                      const InputDecoration(hintText: "Delegate1 to vote"),
                ),
                TextField(
                  controller: _percentController,
                  decoration: const InputDecoration(hintText: "Percent"),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: _vote2Controller,
                  decoration:
                      const InputDecoration(hintText: "Delegate2 to vote"),
                ),
                Row(
                  children: [
                    FlatButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      child: const Text("Cancel"),
                    ),
                    ElevatedButton(
                      onPressed: () => voteForDelegate(
                        context,
                        walletUIModel,
                        _vote1Controller.text,
                        _vote2Controller.text,
                        double.tryParse(_percentController.text) ?? 100,
                      ),
                      child: const Text("Vote"),
                    ),
                  ],
                )
              ],
            ),
          );
        });
  }

  Future<dynamic> _onWalletLongClicked(
      BuildContext context, WalletUIModel walletUIModel) async {
    return showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Are you sure to delete this wallet?'),
            actions: [
              FlatButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: () => _deleteWallet(
                  context,
                  walletUIModel,
                ),
                child: const Text("Delete"),
              ),
            ],
          );
        });
  }

  Future<void> voteForDelegate(
    BuildContext context,
    WalletUIModel walletUIModel,
    String delegate1Name,
    String delegate2Name,
    double percentage,
  ) async {
    final passphrases = await _loadPassphrases();
    final walletResponse =
        await _client.wallets.getWallet(walletAddress: walletUIModel.address);
    final nonce = int.tryParse(walletResponse.data?.nonce ?? "0") ?? 0;
    final voteTransaction = createVoteTransaction(
      passphrase: passphrases[walletUIModel.label] ?? "",
      nonce: nonce + 1,
      delegate1: delegate1Name,
      delegate2: delegate2Name,
      percentage: percentage,
    );
    final transactionBroadcastResponse =
        await _client.transactions.broadcastTransactions(
      broadcastTransactionsRequest:
          BroadcastTransactionsRequest.fromTransaction(voteTransaction),
    );
    Navigator.of(context).pop();
    if (transactionBroadcastResponse.errors != null) {
      showBanner(
        context,
        Colors.red,
        jsonEncode(transactionBroadcastResponse.errors),
      );
    } else {
      showBanner(
        context,
        Colors.green,
        "Success",
      );
    }
  }

  VoteTransaction createVoteTransaction({
    required String passphrase,
    required int nonce,
    required String delegate1,
    required String? delegate2,
    required double percentage,
  }) {
    VoteTransaction? voteTransaction;
    if (delegate2 != null && percentage.round() != 100) {
      final percentage1 = percentage.toInt();
      final percentage2 = 100 - percentage1;
      voteTransaction = VoteTransaction(
        {delegate1: percentage1.toDouble(), delegate2: percentage2.toDouble()},
        passphrase: passphrase,
        fee: 2000000,
      );
    } else {
      voteTransaction = VoteTransaction(
        {delegate1: 100},
        passphrase: passphrase,
        fee: 2000000,
      );
    }

    voteTransaction.network = Mainnet().version();
    voteTransaction.nonce = nonce;
    voteTransaction.expiration = 0;
    voteTransaction.senderPublicKey = PublicKey.fromPassphrase(passphrase);

    voteTransaction.schnorrSign(passphrase);
    return voteTransaction;
  }

  void _deleteWallet(BuildContext context, WalletUIModel walletUIModel) async {
    final Map<String, String> newPassphrases = await _loadPassphrases();
    newPassphrases.remove(walletUIModel.label);
    final store = await BiometricStorage().getStorage('storage');
    await store.write(jsonEncode(newPassphrases));
    _loadContent(newPassphrases);
    Navigator.of(context).pop();
  }

  void showBanner(
      BuildContext context, Color backgroundColor, String message) async {
    Flushbar(
      duration: const Duration(seconds: 2),
      message: message,
      backgroundColor: backgroundColor,
      messageColor: Colors.white,
    ).show(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Remote voter"),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _addPassphrase(),
            _isLoading ? _loading() : _walletsListView(),
            ElevatedButton(
              onPressed: () async => _loadContent(await _loadPassphrases()),
              child: const Text("Refresh"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _addPassphrase() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              decoration: const InputDecoration(hintText: "label"),
              controller: _labelController,
              minLines: 1,
              keyboardType: TextInputType.text,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 280,
                child: TextField(
                  decoration: const InputDecoration(hintText: "passphrase"),
                  controller: _passphraseController,
                  minLines: 1,
                  maxLines: 4,
                  keyboardType: TextInputType.visiblePassword,
                  enableSuggestions: false,
                  autocorrect: false,
                  obscureText: false,
                ),
              ),
              ElevatedButton(
                onPressed: _addPassphraseClicked,
                child: const Text("Add"),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _loading() {
    return const Center(
      child: CircularProgressIndicator(),
    );
  }

  Widget _walletsListView() {
    return ListView.builder(
      physics: const ClampingScrollPhysics(),
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      itemBuilder: (context, i) {
        return InkWell(
          onTap: () => _onWalletClicked(context, _wallets[i]),
          onLongPress: () => _onWalletLongClicked(context, _wallets[i]),
          child: Container(
            margin: const EdgeInsets.all(10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black26, width: 1),
              borderRadius: const BorderRadius.all(Radius.circular(10)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_wallets[i].label),
                Text(_wallets[i].address),
                Text(
                    "${(int.tryParse(_wallets[i].balance) ?? 0) ~/ 100000000}"),
                Text("Voting for: ${_wallets[i].votingFor ?? ""} ${_wallets[i].percentage}"),
              ],
            ),
          ),
        );
      },
      itemCount: _wallets.length,
    );
  }
}
