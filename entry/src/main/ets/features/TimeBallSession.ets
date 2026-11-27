import { abilityAccessCtrl, common, Permissions, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { floatingBall } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x4642;
const TAG: string = 'TimeBall';
const TICK_MS: number = 1000;

export type TimeBallPhase = 'idle' | 'creating' | 'started' | 'stopping';

/**
 * 闪控球时钟：每秒 updateFloatingBall，展示当前时分秒。
 */
export class TimeBallSession {
  private static instance: TimeBallSession = new TimeBallSession();

  private phase: TimeBallPhase = 'idle';
  private ballCtrl: floatingBall.FloatingBallController | undefined = undefined;
  private tickId: number = -1;
  private clickHandler: (() => void) | undefined = undefined;
  private stateHandler: ((state: floatingBall.FloatingBallState) => void) | undefined = undefined;

  static get(): TimeBallSession {
    return TimeBallSession.instance;
  }

  isRunning(): boolean {
    return this.phase === 'started' || this.phase === 'creating';
  }

  async start(context: common.UIAbilityContext): Promise<string> {
    if (this.phase === 'creating' || this.phase === 'started') {
      return '闪控球已在运行';
    }
    if (!canIUse('SystemCapability.Window.SessionManager') || !floatingBall.isFloatingBallEnabled()) {
      return '当前设备不支持闪控球';
    }

    this.phase = 'creating';

    const granted: boolean = await TimeBallSession.requestPermission(context);
    if (!granted) {
      this.phase = 'idle';
      return '需要 ohos.permission.USE_FLOAT_BALL 权限（受限权限，需 ACL）';
    }

    try {
      this.ballCtrl = await floatingBall.create({ context: context });
      this.registerListeners(context);

      const params: floatingBall.FloatingBallParams = TimeBallSession.buildParams();
      await this.ballCtrl.startFloatingBall(params);
      this.startTicker();
      this.phase = 'started';
      AppStorage.setOrCreate('timeBallActive', true);
      AppStorage.setOrCreate('timeBallClock', TimeBallSession.formatClock(new Date()));
      hilog.info(DOMAIN, TAG, 'time ball started');
      return '';
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      hilog.error(DOMAIN, TAG, `start failed: ${err.code} ${err.message}`);
      await this.forceCleanup();
      return `启动失败 ${err.code}: ${err.message}`;
    }
  }

  async stop(): Promise<void> {
    if (this.phase === 'idle' || this.phase === 'stopping') {
      return;
    }
    this.phase = 'stopping';
    this.stopTicker();
    try {
      if (this.ballCtrl) {
        await this.ballCtrl.stopFloatingBall();
      }
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      hilog.warn(DOMAIN, TAG, `stop err: ${err.code} ${err.message}`);
    }
    await this.forceCleanup();
  }

  private registerListeners(context: common.UIAbilityContext): void {
    if (!this.ballCtrl) {
      return;
    }

    this.clickHandler = (): void => {
      const want: Want = {
        bundleName: context.abilityInfo.bundleName,
        abilityName: 'EntryAbility'
      };
      this.ballCtrl?.restoreMainWindow(want).catch((err: BusinessError) => {
        hilog.warn(DOMAIN, TAG, `restoreMainWindow failed: ${err.code}`);
      });
    };
    try {
      this.ballCtrl.on('click', this.clickHandler);
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      hilog.warn(DOMAIN, TAG, `on click failed: ${err.code}`);
    }

    this.stateHandler = (state: floatingBall.FloatingBallState): void => {
      hilog.info(DOMAIN, TAG, `state=${state}`);
      if (state === floatingBall.FloatingBallState.STOPPED) {
        void this.forceCleanup();
      }
    };
    try {
      this.ballCtrl.on('stateChange', this.stateHandler);
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      hilog.warn(DOMAIN, TAG, `on stateChange failed: ${err.code}`);
    }
  }

  private startTicker(): void {
    this.stopTicker();
    this.tickId = setInterval((): void => {
      this.refreshBall();
    }, TICK_MS);
  }

  private stopTicker(): void {
    if (this.tickId >= 0) {
      clearInterval(this.tickId);
      this.tickId = -1;
    }
  }

  private refreshBall(): void {
    if (this.phase !== 'started' || !this.ballCtrl) {
      return;
    }
    const now: Date = new Date();
    const clockText: string = TimeBallSession.formatClock(now);
    AppStorage.setOrCreate('timeBallClock', clockText);
    const params: floatingBall.FloatingBallParams = TimeBallSession.buildParams(now);
    this.ballCtrl.updateFloatingBall(params).catch((err: BusinessError) => {
      hilog.warn(DOMAIN, TAG, `update failed: ${err.code}`);
    });
  }

  private static buildParams(now: Date = new Date()): floatingBall.FloatingBallParams {
    return {
      template: floatingBall.FloatingBallTemplate.NORMAL,
      title: '时钟',
      content: TimeBallSession.formatClock(now),
      backgroundColor: '#1A73E8'
    };
  }

  private static formatClock(now: Date): string {
    const hh: string = TimeBallSession.pad2(now.getHours());
    const mm: string = TimeBallSession.pad2(now.getMinutes());
    const ss: string = TimeBallSession.pad2(now.getSeconds());
    return `${hh}:${mm}:${ss}`;
  }

  private static pad2(n: number): string {
    if (n < 10) {
      return `0${n}`;
    }
    return `${n}`;
  }

  private async forceCleanup(): Promise<void> {
    this.stopTicker();
    if (this.ballCtrl) {
      try {
        if (this.clickHandler) {
          this.ballCtrl.off('click', this.clickHandler);
        } else {
          this.ballCtrl.off('click');
        }
      } catch (_e) {
        // ignore
      }
      try {
        if (this.stateHandler) {
          this.ballCtrl.off('stateChange', this.stateHandler);
        } else {
          this.ballCtrl.off('stateChange');
        }
      } catch (_e) {
        // ignore
      }
    }
    this.ballCtrl = undefined;
    this.clickHandler = undefined;
    this.stateHandler = undefined;
    this.phase = 'idle';
    AppStorage.setOrCreate('timeBallActive', false);
  }

  private static async requestPermission(context: common.UIAbilityContext): Promise<boolean> {
    const permissions: Array<Permissions> = ['ohos.permission.USE_FLOAT_BALL'];
    try {
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const result = await atManager.requestPermissionsFromUser(context, permissions);
      for (let i = 0; i < result.authResults.length; i++) {
        if (result.authResults[i] !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
          return false;
        }
      }
      return true;
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      hilog.error(DOMAIN, TAG, `perm failed: ${err.code} ${err.message}`);
      return false;
    }
  }
}
