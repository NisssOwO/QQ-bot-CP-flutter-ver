import assert from 'node:assert/strict';
import {
    activeOverride,
    dayKindOf,
    DEFAULT_SETTINGS,
    formatClock,
    isQuietAt,
    normalizeSettings,
    normalizeWindows,
    parseClock,
    utc8Parts,
    windowContains,
    windowEndMs,
} from '../node_modules/@tencent-connect/dsh-qqbot/dist/middleware/quiet-hours.js';

// 现役中间件的静默判定（dist/middleware/quiet-hours.js）。
// 注意与同目录 quiet-hours.mjs 区分：那份是早期自研管道的全链路免打扰实现，
// 这份只挡主动插话。这里守住判定本身：时区换算、跨夜窗口、工作日/节假日、临时覆盖。

const beijing = (year, month, day, hour, minute) => new Date(Date.UTC(year, month - 1, day, hour - 8, minute));

// 1) 时区换算：北京时间 2026-11-18 23:30（周三）
{
    const parts = utc8Parts(beijing(2026, 11, 18, 23, 30));
    assert.equal(parts.date, '2026-11-18');
    assert.equal(parts.isoDow, 3);
    assert.equal(parts.minutes, 23 * 60 + 30);
    assert.equal(parts.localTime, '23:30');
}

// 2) 时间文本解析/格式化
{
    assert.equal(parseClock('23:00'), 1380);
    assert.equal(parseClock('8:05'), 485);
    assert.equal(parseClock('24:00'), undefined);
    assert.equal(parseClock('23:60'), undefined);
    assert.equal(parseClock(''), undefined);
    assert.equal(formatClock(1380), '23:00');
    assert.equal(formatClock(0), '00:00');
    assert.equal(formatClock(-60), '23:00');
}

// 3) 窗口规范化：字符串/数字都接受，起止相同与非法项丢弃，非数组返回 undefined
{
    assert.deepEqual(normalizeWindows([['23:00', '08:00'], ['12:00', '12:00'], ['x', 'y'], [1380, 480]]), [[1380, 480], [1380, 480]]);
    assert.deepEqual(normalizeWindows([[540, 720]]), [[540, 720]]);
    assert.equal(normalizeWindows('nope'), undefined);
    assert.deepEqual(normalizeWindows([]), []);
}

// 4) 窗口命中：跨夜与非跨夜
{
    assert.equal(windowContains([1380, 480], 23 * 60 + 30), true); // 23:30
    assert.equal(windowContains([1380, 480], 3 * 60 + 20), true); // 凌晨 03:20
    assert.equal(windowContains([1380, 480], 12 * 60), false); // 中午
    assert.equal(windowContains([540, 720], 10 * 60), true); // 09:00-12:00 里
    assert.equal(windowContains([540, 720], 12 * 60), false); // 右端开区间
    assert.equal(windowContains([540, 540], 600), false); // 起止相同视为无效
}

// 5) 窗口结束时刻：跨夜窗口的深夜时段结束在次日，凌晨时段结束在当天
{
    const late = windowEndMs(beijing(2026, 11, 18, 23, 30).getTime(), [1380, 480]);
    assert.equal(utc8Parts(new Date(late)).date, '2026-11-19');
    assert.equal(utc8Parts(new Date(late)).localTime, '08:00');
    const early = windowEndMs(beijing(2026, 11, 18, 3, 0).getTime(), [1380, 480]);
    assert.equal(utc8Parts(new Date(early)).date, '2026-11-18');
    assert.equal(utc8Parts(new Date(early)).localTime, '08:00');
}

// 6) 配置补全：空对象给默认值，非法项被丢弃
{
    assert.deepEqual(normalizeSettings(undefined), DEFAULT_SETTINGS);
    assert.deepEqual(normalizeSettings({}), DEFAULT_SETTINGS);
    assert.equal(normalizeSettings({ enabled: false }).enabled, false);
    assert.equal(normalizeSettings({ holidays: 'none' }).holidays, 'none');
    assert.equal(normalizeSettings({ holidays: 'bogus' }).holidays, 'cn');
    assert.deepEqual(normalizeSettings({ workday: { weekdays: [1, 1, 9, 0] } }).workdays, [1]);
    assert.deepEqual(normalizeSettings({ workday: { weekdays: [] } }).workdays, DEFAULT_SETTINGS.workdays);
    assert.deepEqual(normalizeSettings({ workday: { windows: [] } }).workdayWindows, []);
}

// 7) 工作日/休息日：星期规则 + 节假日表（holiday=true 放假，false 调休上班）
{
    const workday = utc8Parts(beijing(2026, 11, 18, 21, 0)); // 周三
    const saturday = utc8Parts(beijing(2026, 11, 21, 21, 0));
    const settings = normalizeSettings({});
    assert.equal(dayKindOf(workday, settings, {}), 'workday');
    assert.equal(dayKindOf(saturday, settings, {}), 'offday');
    assert.equal(dayKindOf(workday, settings, { '2026-11-18': { holiday: true, name: '测试节' } }), 'offday');
    assert.equal(dayKindOf(saturday, settings, { '2026-11-21': { holiday: false, name: '调休' } }), 'workday');
}

// 8) 判定：默认配置下 23:30 静默、中午正常、关闭后不静默
{
    const settings = normalizeSettings({});
    const late = isQuietAt({ nowMs: beijing(2026, 11, 18, 23, 30).getTime(), settings, days: {} });
    assert.equal(late.state, 'quiet');
    assert.equal(late.dayKind, 'workday');
    assert.equal(late.window, '23:00-08:00');
    assert.equal(utc8Parts(new Date(late.until)).localTime, '08:00');
    const noon = isQuietAt({ nowMs: beijing(2026, 11, 18, 12, 0).getTime(), settings, days: {} });
    assert.equal(noon.state, 'normal');
    assert.equal(noon.window, '');
    const disabled = normalizeSettings({ enabled: false });
    assert.equal(isQuietAt({ nowMs: beijing(2026, 11, 18, 23, 30).getTime(), settings: disabled, days: {} }).state, 'normal');
}

// 9) 休息日窗口默认延长到 09:00；法定节假日名称进状态
{
    const settings = normalizeSettings({});
    const saturday = isQuietAt({ nowMs: beijing(2026, 11, 21, 8, 30).getTime(), settings, days: {} });
    assert.equal(saturday.dayKind, 'offday');
    assert.equal(saturday.state, 'quiet');
    assert.equal(utc8Parts(new Date(saturday.until)).localTime, '09:00');
    const holiday = isQuietAt({
        nowMs: beijing(2026, 11, 18, 23, 30).getTime(),
        settings,
        days: { '2026-11-18': { holiday: true, name: '测试节' } },
    });
    assert.equal(holiday.dayKind, 'offday');
    assert.equal(holiday.holiday, '测试节');
}

// 10) 临时覆盖：生效时状态变 override，过期后回到原判定
{
    const settings = normalizeSettings({});
    const now = beijing(2026, 11, 18, 23, 30).getTime();
    const covering = isQuietAt({ nowMs: now, settings, days: {}, override: { kind: 'minutes', until: now + 15 * 60_000 } });
    assert.equal(covering.state, 'override');
    assert.equal(covering.until, now + 15 * 60_000);
    const expired = isQuietAt({ nowMs: now, settings, days: {}, override: { kind: 'minutes', until: now - 1000 } });
    assert.equal(expired.state, 'quiet');
    assert.equal(activeOverride({ kind: 'day', until: now + 1000 }, now)?.kind, 'day');
    assert.equal(activeOverride({ kind: 'day', until: now - 1000 }, now), null);
    assert.equal(activeOverride(null, now), null);
}

// 11) 覆盖也不影响"不静默"时段：白天点"今天不再静默"只是把状态标成 override
{
    const settings = normalizeSettings({});
    const noon = beijing(2026, 11, 18, 12, 0).getTime();
    const state = isQuietAt({ nowMs: noon, settings, days: {}, override: { kind: 'day', until: noon + 60 * 60_000 } });
    assert.equal(state.state, 'override');
}

console.log('test-middleware-quiet-hours: all assertions passed');
