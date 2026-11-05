import 'package:flutter/material.dart';

import 'home_page.dart';
import 'models/auth_models.dart';
import 'services/auth_service.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final LocalAuthService _authService = LocalAuthService();

  AuthSnapshot? _snapshot;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSnapshot();
  }

  Future<void> _loadSnapshot() async {
    final snapshot = await _authService.loadSnapshot();
    if (!mounted) {
      return;
    }

    setState(() {
      _snapshot = snapshot;
      _isLoading = false;
    });
  }

  Future<String?> _handleLogin({
    required String username,
    required String password,
  }) async {
    try {
      final user = await _authService.login(
        username: username,
        password: password,
      );
      if (user == null) {
        return 'Invalid username or password.';
      }
      await _loadSnapshot();
      return null;
    } on AuthException catch (error) {
      return error.message;
    } catch (_) {
      return 'Could not sign in. Please try again.';
    }
  }

  Future<void> _handleLogout() async {
    await _authService.logout();
    await _loadSnapshot();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _snapshot == null) {
      return const _AuthLoadingScreen();
    }

    if (_snapshot!.isAuthenticated) {
      return HomePage(
        currentUser: _snapshot!.currentUser!,
        onLogout: _handleLogout,
      );
    }

    return _LoginScreen(onSubmit: _handleLogin);
  }
}

class _AuthLoadingScreen extends StatelessWidget {
  const _AuthLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Stack(
        children: <Widget>[
          _AuthBackdrop(),
          Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}

class _LoginScreen extends StatelessWidget {
  const _LoginScreen({required this.onSubmit});

  final Future<String?> Function({
    required String username,
    required String password,
  })
  onSubmit;

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      eyebrow: 'Committee login',
      title: 'Sign in to continue',
      subtitle:
          'Use the saved admin account to access houses, reports, and payment records.',
      icon: Icons.lock_open_rounded,
      child: _LoginForm(onSubmit: onSubmit),
    );
  }
}

class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Stack(
        children: <Widget>[
          const _AuthBackdrop(),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    children: <Widget>[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(32),
                          gradient: const LinearGradient(
                            colors: <Color>[
                              Color(0xFF0E2A30),
                              Color(0xFF173E44),
                              Color(0xFF9F7347),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: const <BoxShadow>[
                            BoxShadow(
                              color: Color(0x26112F33),
                              blurRadius: 30,
                              offset: Offset(0, 16),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Container(
                              width: 58,
                              height: 58,
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(18),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.white.withAlpha(28),
                                ),
                              ),
                              child: Icon(icon, color: Colors.white),
                            ),
                            const SizedBox(height: 22),
                            Text(
                              eyebrow.toUpperCase(),
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: Colors.white.withAlpha(190),
                                letterSpacing: 0.8,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              title,
                              style: theme.textTheme.headlineMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              subtitle,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: Colors.white.withAlpha(214),
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(232),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: theme.colorScheme.outline.withAlpha(28),
                          ),
                          boxShadow: const <BoxShadow>[
                            BoxShadow(
                              color: Color(0x140E2A30),
                              blurRadius: 24,
                              offset: Offset(0, 14),
                            ),
                          ],
                        ),
                        child: child,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginForm extends StatefulWidget {
  const _LoginForm({required this.onSubmit});

  final Future<String?> Function({
    required String username,
    required String password,
  })
  onSubmit;

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isSubmitting = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final error = await widget.onSubmit(
      username: _usernameController.text.trim(),
      password: _passwordController.text,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isSubmitting = false;
    });

    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Login details',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Only authorized committee members should use this login to access masjid subscription data.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          TextFormField(
            controller: _usernameController,
            decoration: const InputDecoration(labelText: 'Username'),
            textInputAction: TextInputAction.next,
            validator: (String? value) {
              if (value == null || value.trim().isEmpty) {
                return 'Enter your username';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _passwordController,
            decoration: InputDecoration(
              labelText: 'Password',
              suffixIcon: IconButton(
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
            ),
            obscureText: _obscurePassword,
            onFieldSubmitted: (_) {
              _submit();
            },
            validator: (String? value) {
              if (value == null || value.isEmpty) {
                return 'Enter your password';
              }
              return null;
            },
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _isSubmitting ? null : _submit,
              icon: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.login_rounded),
              label: Text(_isSubmitting ? 'Signing in...' : 'Sign in'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AuthBackdrop extends StatelessWidget {
  const _AuthBackdrop();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: <Widget>[
          Positioned(
            top: -150,
            right: -70,
            child: Container(
              width: 280,
              height: 280,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[Color(0x40C18A53), Color(0x00C18A53)],
                ),
              ),
            ),
          ),
          Positioned(
            top: 120,
            left: -100,
            child: Container(
              width: 240,
              height: 240,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[Color(0x351A5E57), Color(0x001A5E57)],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -120,
            right: -40,
            child: Container(
              width: 240,
              height: 240,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[Color(0x24112F33), Color(0x00112F33)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
