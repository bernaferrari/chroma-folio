import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_ui/material_ui.dart';

import '../blocs/studio_cubit.dart';
import '../widgets/channel_reel.dart';

/// Three reels side by side, one for each channel of the active colour space.
class const PickerScreen({super.key}) extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<StudioCubit, StudioState>(
      buildWhen: (prev, next) =>
          prev.activeColor != next.activeColor ||
          prev.activeSpace != next.activeSpace,
      builder: (context, state) {
        final cubit = context.read<StudioCubit>();
        final channels = state.activeColor.channelsFor(state.activeSpace);
        return LayoutBuilder(
          builder: (context, constraints) {
            final gap = constraints.maxWidth < 520 ? 10.0 : 16.0;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final channel in channels) ...[
                  if (channel.index > 0) SizedBox(width: gap),
                  Expanded(
                    child: ChannelReel(
                      key: ValueKey<int>(channel.index),
                      descriptor: channel,
                      space: state.activeSpace,
                      activeColor: state.activeColor,
                      onScrubStart: cubit.beginScrub,
                      onScrubUpdate: (value) =>
                          cubit.scrubChannel(channel.index, value),
                      onScrubEnd: cubit.endScrub,
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }
}
