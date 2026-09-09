import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/auth_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _key = TextEditingController();
  final _url = TextEditingController(text: defaultWandbBaseUrl);
  bool _connecting = false;
  bool _dedicated = false;
  bool _obscure = true;
  String? _validationError;

  @override
  void dispose() {
    _key.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final key = _key.text.trim();
    final url = Uri.tryParse(_url.text.trim());
    if (key.isEmpty) {
      setState(() => _validationError = 'Enter your API key');
      return;
    }
    if (url == null ||
        url.scheme != 'https' ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        url.hasQuery ||
        url.hasFragment) {
      setState(() => _validationError = 'Enter a valid HTTPS server URL');
      return;
    }
    setState(() => _validationError = null);
    await ref
        .read(authProvider.notifier)
        .login(apiKey: key, baseUrl: url.toString());
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final loading = auth.status == AuthStatus.loading;
    if (_connecting) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_dedicated ? 'Dedicated Cloud' : 'Log in'),
          leading: IconButton(
            tooltip: 'Back',
            onPressed:
                loading ? null : () => setState(() => _connecting = false),
            icon: const Icon(Icons.arrow_back_ios_new),
          ),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Connect to Weights & Biases',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    const Text('Use your W&B API key to connect your account.'),
                    TextButton(
                      onPressed:
                          () => launchUrl(
                            Uri.parse('https://wandb.ai/authorize'),
                            mode: LaunchMode.externalApplication,
                          ),
                      child: const Text('Get your API key'),
                    ),
                    const SizedBox(height: 20),
                    if (_dedicated) ...[
                      TextField(
                        controller: _url,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Server URL',
                          hintText: 'https://your-instance.wandb.io',
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextField(
                      controller: _key,
                      obscureText: _obscure,
                      autocorrect: false,
                      enableSuggestions: false,
                      autofillHints: null,
                      onSubmitted: (_) => _login(),
                      decoration: InputDecoration(
                        labelText: 'API key',
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip:
                                  _obscure ? 'Show API key' : 'Hide API key',
                              onPressed:
                                  () => setState(() => _obscure = !_obscure),
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Paste API key',
                              onPressed: () async {
                                final data = await Clipboard.getData(
                                  'text/plain',
                                );
                                if (mounted && data?.text != null)
                                  _key.text = data!.text!.trim();
                              },
                              icon: const Icon(Icons.content_paste),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_validationError != null || auth.error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          _validationError ?? auth.error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: loading ? null : _login,
                      child:
                          loading
                              ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Text('Log in'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF111111),
        body: SafeArea(
          child: LayoutBuilder(
            builder:
                (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 24,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset(
                            'assets/icons/login_logo.png',
                            width: 176,
                            height: 250,
                            fit: BoxFit.contain,
                            semanticLabel: 'Weights & Biases by CoreWeave',
                          ),
                          const SizedBox(height: 56),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFFFBE00),
                                foregroundColor: Colors.black,
                              ),
                              onPressed:
                                  loading
                                      ? null
                                      : () => setState(() {
                                        _connecting = true;
                                        _dedicated = false;
                                        _url.text = defaultWandbBaseUrl;
                                      }),
                              child:
                                  loading
                                      ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                      : const Text('Log in'),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                minimumSize: const Size(48, 48),
                                side: const BorderSide(color: Colors.white24),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed:
                                  loading
                                      ? null
                                      : () => setState(() {
                                        _connecting = true;
                                        _dedicated = true;
                                        _url.clear();
                                      }),
                              child: const Text('Log in to Dedicated Cloud'),
                            ),
                          ),
                          const SizedBox(height: 28),
                          const Text(
                            'Not yet available for On-prem accounts.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                            ),
                          ),
                          Wrap(
                            alignment: WrapAlignment.center,
                            children: [
                              TextButton(
                                onPressed:
                                    () => launchUrl(
                                      Uri.parse('https://site.wandb.ai/terms/'),
                                    ),
                                child: const Text(
                                  'Master Service Agreement',
                                  style: TextStyle(
                                    color: Colors.white60,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed:
                                    () => launchUrl(
                                      Uri.parse(
                                        'https://site.wandb.ai/privacy/',
                                      ),
                                    ),
                                child: const Text(
                                  'Privacy Policy',
                                  style: TextStyle(
                                    color: Colors.white60,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (auth.error != null)
                            Text(
                              auth.error!,
                              style: const TextStyle(color: Colors.redAccent),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
          ),
        ),
      ),
    );
  }
}
