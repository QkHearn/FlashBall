import { common } from '@kit.AbilityKit';
import { TimeBallSession } from '../features/TimeBallSession';

@Entry
@Component
struct Index {
  @State ballRunning: boolean = false;
  @StorageLink('timeBallClock') clockText: string = '--:--:--';
  @State statusTip: string = '点击下方按钮启动闪控球，每秒刷新当前时间';

  aboutToAppear(): void {
    AppStorage.setOrCreate('timeBallActive', false);
    AppStorage.setOrCreate('timeBallClock', '--:--:--');
    this.ballRunning = TimeBallSession.get().isRunning();
  }

  private async onStartBall(): Promise<void> {
    const host = this.getUIContext().getHostContext();
    if (!host) {
      this.statusTip = '无法获取 AbilityContext';
      return;
    }
    const context: common.UIAbilityContext = host as common.UIAbilityContext;
    const errMsg: string = await TimeBallSession.get().start(context);
    if (errMsg.length > 0) {
      this.statusTip = errMsg;
      this.ballRunning = false;
      try {
        this.getUIContext().getPromptAction().showToast({ message: errMsg, duration: 2500 });
      } catch (_e) {
        // ignore toast failure
      }
      return;
    }
    this.ballRunning = true;
    this.statusTip = '闪控球已启动，退到后台仍可看见时钟胶囊（定时器可能被系统冻结）';
  }

  private async onStopBall(): Promise<void> {
    await TimeBallSession.get().stop();
    this.ballRunning = false;
    this.statusTip = '闪控球已停止';
  }

  build() {
    Column({ space: 20 }) {
      Text('闪控球时钟')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1A1A1A')

      Text(this.clockText)
        .fontSize(48)
        .fontWeight(FontWeight.Medium)
        .fontColor('#1A73E8')
        .fontFamily('monospace')
        .margin({ top: 8, bottom: 8 })

      Text(this.statusTip)
        .fontSize(14)
        .fontColor('#666666')
        .textAlign(TextAlign.Center)
        .padding({ left: 24, right: 24 })

      if (this.ballRunning) {
        Button('停止闪控球')
          .width('70%')
          .height(48)
          .backgroundColor('#E53935')
          .onClick(() => {
            void this.onStopBall();
          })
      } else {
        Button('启动闪控球')
          .width('70%')
          .height(48)
          .backgroundColor('#1A73E8')
          .onClick(() => {
            void this.onStartBall();
          })
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#F5F7FA')
  }
}
