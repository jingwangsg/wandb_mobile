import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/colors.dart';
import '../providers/auth_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _apiKeyController = TextEditingController();
  final _baseUrlController = TextEditingController();
  bool _showAdvanced = false;
  bool _obscureKey = true;

  @override
  void dispose() {
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) return;

    final baseUrl = _baseUrlController.text.trim();
    await ref.read(authProvider.notifier).login(
          apiKey: apiKey,
          baseUrl: baseUrl.isNotEmpty ? baseUrl : null,
        );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final isLoading = authState.status == AuthStatus.loading;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo / Title
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: WandbColors.yellow,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Center(
                    child: Text(
                      'W&B',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'W&B Mobile',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter your API key to get started',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white54,
                      ),
                ),
                const SizedBox(height: 40),

                // API Key Input
                TextField(
                  controller: _apiKeyController,
                  obscureText: _obscureKey,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'API Key',
                    hintText: 'Paste your wandb API key',
                    prefixIcon: const Icon(Icons.key),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            _obscureKey
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () =>
                              setState(() => _obscureKey = !_obscureKey),
                        ),
                        IconButton(
                          icon: const Icon(Icons.paste),
                          onPressed: () async {
                            final data =
                                await Clipboard.getData('text/plain');
                            if (data?.text != null) {
                              _apiKeyController.text = data!.text!.trim();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  onSubmitted: (_) => _login(),
                ),
                const SizedBox(height: 16),

                // Advanced options
                GestureDetector(
                  onTap: () =>
                      setState(() => _showAdvanced = !_showAdvanced),
                  child: Row(
                    children: [
                      Icon(
                        _showAdvanced
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 20,
                        color: Colors.white38,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Advanced',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.white38,
                            ),
                      ),
                    ],
                  ),
                ),
                if (_showAdvanced) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _baseUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Base URL (optional)',
                      hintText: 'https://api.wandb.ai',
                      prefixIcon: Icon(Icons.link),
                    ),
                  ),
                ],
                const SizedBox(height: 24),

                // Error
                if (authState.error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      authState.error!,
                      style: const TextStyle(color: WandbColors.failed),
                    ),
                  ),

                // Login button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: isLoading ? null : _login,
                    style: FilledButton.styleFrom(
                      backgroundColor: WandbColors.yellow,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            'Connect',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Find your API key at wandb.ai/authorize',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white38,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
