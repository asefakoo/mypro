import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class ServicesScreen extends StatelessWidget {
  const ServicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080B12), // Deeper midnight navy
      body: Stack(
        children: [
          // 1. Ambient Background Elements
          _buildAmbientGlow(context),

          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Determine layout density based on available width
                final double width = constraints.maxWidth;
                final double horizontalPadding = width > 1200 ? width * 0.15 : width * 0.06;

                return Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                  child: CustomScrollView(
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      // Animated Header Section
                      SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 40),
                            _buildHeader(width),
                            const SizedBox(height: 24),
                            _buildAccessStatus(width),
                            const SizedBox(height: 40),
                          ],
                        ),
                      ),

                      // Responsive Grid
                      SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: width > 1200 ? 4 : (width > 700 ? 3 : 2),
                          crossAxisSpacing: 20,
                          mainAxisSpacing: 20,
                          childAspectRatio: 0.85, // Taller cards feel more premium
                        ),
                        delegate: SliverChildListDelegate([
                          _ServiceCard(title: "DATA VAULT", icon: CupertinoIcons.lock_shield, subtitle: "Secure Storage", color: Colors.cyanAccent),
                          _ServiceCard(title: "NETWORK", icon: CupertinoIcons.antenna_radiowaves_left_right, subtitle: "Encrypted Proxy", color: Colors.blueAccent),
                          _ServiceCard(title: "NEURAL LINK", icon: CupertinoIcons.suit_club, subtitle: "AI Processing", color: Colors.purpleAccent),
                          _ServiceCard(title: "ANALYTICS", icon: CupertinoIcons.chart_bar_alt_fill, subtitle: "Real-time Data", color: Colors.orangeAccent),
                          _ServiceCard(title: "MESSAGES", icon: CupertinoIcons.chat_bubble_2, subtitle: "Secure Comms", color: Colors.greenAccent),
                          _ServiceCard(title: "SYSTEM", icon: CupertinoIcons.settings, subtitle: "Config Tools", color: Colors.redAccent),
                        ]),
                      ),

                      // Footer
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _buildFooter(width),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmbientGlow(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: -100,
          right: -50,
          child: _GlowCircle(color: Colors.cyanAccent.withOpacity(0.12), size: 300),
        ),
        Positioned(
          bottom: -50,
          left: -50,
          child: _GlowCircle(color: Colors.indigoAccent.withOpacity(0.1), size: 250),
        ),
      ],
    );
  }

  Widget _buildHeader(double width) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: const BoxDecoration(color: Colors.cyanAccent, shape: BoxShape.circle),
            ),
            const SizedBox(width: 12),
            Text(
              "SYSTEM OPERATIONAL",
              style: TextStyle(
                color: Colors.cyanAccent.withOpacity(0.8),
                letterSpacing: 3,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          "Service Terminal",
          style: TextStyle(
            color: Colors.white,
            fontSize: width > 600 ? 48 : 32,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildAccessStatus(double width) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(CupertinoIcons.shield_fill, color: Colors.greenAccent, size: 24),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("ENCRYPTED UPLINK ACTIVE",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                    Text("NODE: ${DateTime.now().millisecond} // BYPASS: DISABLED",
                        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11, fontFamily: 'monospace')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(double width) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        const SizedBox(height: 60),
        Divider(color: Colors.white.withOpacity(0.05)),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 30),
          child: Text(
            "CORE OS v4.0.2 • QUANTUM ENCRYPTION ENABLED",
            style: TextStyle(
              color: Colors.white.withOpacity(0.2),
              fontSize: 10,
              letterSpacing: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _ServiceCard extends StatefulWidget {
  final String title;
  final IconData icon;
  final String subtitle;
  final Color color;

  const _ServiceCard({required this.title, required this.icon, required this.subtitle, required this.color});

  @override
  State<_ServiceCard> createState() => _ServiceCardState();
}

class _ServiceCardState extends State<_ServiceCard> {
  bool isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => isHovered = true),
      onExit: (_) => setState(() => isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        transform: isHovered ? (Matrix4.identity()..translate(0, -8, 0)) : Matrix4.identity(),
        decoration: BoxDecoration(
          color: isHovered ? widget.color.withOpacity(0.1) : Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isHovered ? widget.color.withOpacity(0.5) : Colors.white.withOpacity(0.08),
            width: 1.5,
          ),
          boxShadow: isHovered ? [BoxShadow(color: widget.color.withOpacity(0.15), blurRadius: 20, spreadRadius: 2)] : [],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
            onTap: () {},
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isHovered ? widget.color : widget.color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      widget.icon,
                      color: isHovered ? Colors.black : widget.color,
                      size: 28,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    widget.title,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.subtitle,
                    style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlowCircle extends StatelessWidget {
  final Color color;
  final double size;
  const _GlowCircle({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color, blurRadius: 100, spreadRadius: 50)],
      ),
    );
  }
}