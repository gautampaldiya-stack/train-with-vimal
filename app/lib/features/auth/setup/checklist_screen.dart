import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/services.dart';
import '../../../core/icons/app_icons.dart';
import '../../../core/theme/theme.dart';
import '../../../core/widgets/client.dart';
import '../auth_frame.dart';
import 'setup_screen.dart';
import 'setup_state.dart';

/// "You're almost there" — the setup checklist after Save & leave (`wl-resume`).
class ChecklistScreen extends StatefulWidget {
  const ChecklistScreen({super.key});
  @override
  State<ChecklistScreen> createState() => _ChecklistScreenState();
}

class _ChecklistScreenState extends State<ChecklistScreen> {
  final st = SetupState.instance;

  @override
  void initState() {
    super.initState();
    st.addListener(_changed);
    st.load().catchError((_) {});
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    st.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = Services.session.me!;
    final ft = st.firstTodo;
    return AuthFrame(
      wide: true,
      brand: BrandKind.steps,
      steps: setupBrand(context),
      foot: [
        CaButton(ft < 0 ? 'See your profile' : 'Continue · ${SetupState.shorts[ft]}',
            onPressed: () => context.go(ft < 0 ? '/setup/done' : '/setup?step=$ft')),
      ],
      children: [
        Row(children: [CaIconBtn(AppIcons.chevronLeft, tooltip: 'Back', onTap: () => context.go(me.pending ? '/pending' : '/home'))]),
        Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 4, children: [
          Text('You’re almost there, ${me.firstName}', style: AppText.s(24, W.w8, ls: -0.24, h: 1.2)),
          Text('Your coach can’t build your plan until these are done.', style: AppText.s(13.5, W.w4, color: AppColors.muted, h: 1.45)),
        ]),
        CaCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text('Your checklist', style: AppText.s(15, W.w8))),
              CaPill('${st.done.length} of 5 done', tone: CaTone.blue),
            ]),
            Padding(padding: const EdgeInsets.fromLTRB(0, 10, 0, 6), child: CaSegments(count: 5, isDone: st.done.contains)),
            for (var i = 0; i < 5; i++)
              CaMenuRow(
                padX: 0,
                lead: st.done.contains(i) ? const CaIconTile(icon: AppIcons.check, tone: CaTone.green) : CaIconTile(text: '${i + 1}'),
                title: SetupState.titles[i],
                sub: SetupState.subs[i],
                trailing: st.done.contains(i)
                    ? const CaPill('Done', tone: CaTone.green)
                    : i == ft
                        ? const CaPill('Next', tone: CaTone.blue)
                        : const CaPill('To do'),
                onTap: () => context.go('/setup?step=$i'),
              ),
          ]),
        ),
        CaHint(st.remindLine, icon: AppIcons.bell, action: 'Change', onAction: () => showLaterSheet(context)),
      ],
    );
  }
}
