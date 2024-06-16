import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web3dart/web3dart.dart';
import 'package:flutter/services.dart';
import 'package:web3dart/crypto.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

void main() async {
  await dotenv.load(fileName: '.env');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: WalletApp(),
    );
  }
}

class WalletApp extends StatefulWidget {
  const WalletApp({super.key});
  
  @override
  WalletAppState createState() => WalletAppState();

}

class WalletAppState extends State<WalletApp> {
  final String apiKey = dotenv.get('API_KEY');
  late final String rpcUrl = 'https://polygon-amoy.infura.io/v3/$apiKey';
  final int chainId = int.parse(dotenv.get('CHAIN_ID'));
  
  late Web3Client _client;
  EthPrivateKey? _credentials;
  EthereumAddress? _ownAddress;
  String? _address;
  String? _balance;
  String? _transactionHash;
  final TextEditingController _toAddressController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _client = Web3Client(rpcUrl, http.Client());
    _loadWallet();
  }

  Future<void> _loadWallet() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? privateKey = prefs.getString('privateKey');
    if (privateKey != null) {
      final credentials = EthPrivateKey.fromHex(privateKey);
      final address = credentials.address;
      _client.getBalance(address).then((EtherAmount result){
        setState(() {
          _balance = _weiToEth(result);
          });
      });
      setState(() {
        _credentials = credentials;
        _ownAddress = address;
        _address = address.hex;
      });
      debugPrint('Loaded Address: $_address');
    }
  }

  Future<void> createWallet() async {
    final credentials = EthPrivateKey.createRandom(Random.secure());
    final address = credentials.address;
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('privateKey', bytesToHex(credentials.privateKey, include0x: true));
    setState(() {
      _credentials = credentials;
      _ownAddress = address;
      _address = address.hex;
      
    });
    debugPrint('New Address: $_address');
    debugPrint('Private Key: ${bytesToHex(credentials.privateKey, include0x: true)}');
  }

  Future<void> send() async {
    if (_credentials == null || _ownAddress == null) {
      debugPrint('Please create a wallet first.');
      return;
    }

    final toAddress = EthereumAddress.fromHex(_toAddressController.text);
    final amountInEth = double.parse(_amountController.text);
    final amountInWei = BigInt.from(amountInEth * 1e18);
    final amount = EtherAmount.fromBigInt(EtherUnit.wei, amountInWei);
    final gasPrice = await _client.getGasPrice();
    final nonce = await _client.getTransactionCount(_ownAddress!, atBlock: const BlockNum.pending());

    if (toAddress.toString() == '') {
      debugPrint('Please set to address.');
      return;
    }

    final transaction = Transaction(
      from: _ownAddress!,
      to: toAddress,
      value: amount,
      gasPrice: gasPrice,
      maxGas: 21000,
      nonce: nonce,
    );

    try {
      final txHash = await _client.sendTransaction(
        _credentials!,
        transaction,
        chainId: chainId,
      );
      _client.getBalance(_ownAddress!).then((EtherAmount result){
        setState(() {
          _balance = _weiToEth(result);
          });
      });
      setState(() {
        _transactionHash = txHash;
      });
      debugPrint('Transaction Hash: $txHash');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Transaction successful: $txHash')),
      );
    } catch (e) {
      debugPrint('Transaction failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Transaction failed: $e')),
      );
    }
  }

  String _weiToEth(EtherAmount wei) {
    final ethAmount = EtherAmount.fromBigInt(EtherUnit.wei, wei.getInWei);
    return ethAmount.getValueInUnit(EtherUnit.ether).toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Web3 Wallet App'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (_address == null) 
            ElevatedButton(
              onPressed: createWallet,
              child: const Text('Create Wallet'),
            ),
            const SizedBox(height: 20),            
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    Text('Address: $_address'),
                    const SizedBox(height: 10),
                    Text('Balance: $_balance MATIC'),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: () {
                        if (_address != null) {
                          Clipboard.setData(ClipboardData(text: _address!));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Address copied to clipboard'))
                          );
                        }
                      },
                      child: const Text('Copy Address'),
                    ),
                  ],
                ),
              ),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 150,
                  child: TextField(
                    controller: _toAddressController,
                    decoration: const InputDecoration(
                      labelText: 'To Address',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _amountController,
                    decoration: const InputDecoration(
                      labelText: 'Amount (MATIC)',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 10),

                ElevatedButton(
                  onPressed: send,
                  child: const Text('Send'),
                ),
              ],
            ),
            if (_transactionHash != null)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text('Transaction Hash: $_transactionHash'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _client.dispose();
    _toAddressController.dispose();
    _amountController.dispose();
    super.dispose();
  }
}
