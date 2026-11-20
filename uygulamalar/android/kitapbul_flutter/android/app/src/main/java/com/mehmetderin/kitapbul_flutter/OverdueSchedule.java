package com.mehmetderin.kitapbul_flutter;

import java.util.Calendar;
import java.util.List;

/** Geciken ödünçler için sabah 09.00 özet bildirimi zamanlaması. */
final class OverdueSchedule {
    private OverdueSchedule() {}

    static long dayStart(long time) {
        Calendar c = Calendar.getInstance();
        c.setTimeInMillis(time);
        c.set(Calendar.HOUR_OF_DAY, 0);
        c.set(Calendar.MINUTE, 0);
        c.set(Calendar.SECOND, 0);
        c.set(Calendar.MILLISECOND, 0);
        return c.getTimeInMillis();
    }

    static long morning(long time, int dayOffset) {
        Calendar c = Calendar.getInstance();
        c.setTimeInMillis(time);
        c.add(Calendar.DAY_OF_YEAR, dayOffset);
        c.set(Calendar.HOUR_OF_DAY, 9);
        c.set(Calendar.MINUTE, 0);
        c.set(Calendar.SECOND, 0);
        c.set(Calendar.MILLISECOND, 0);
        return c.getTimeInMillis();
    }

    /** İade gününden sonraki ilk sabah; geçmişteyse bir sonraki sabah. */
    static Long nextSummary(List<Long> dueTimes, long now) {
        if (dueTimes.isEmpty()) return null;
        long todayMorning = morning(now, 0);
        long nextMorning = todayMorning > now ? todayMorning : morning(now, 1);
        Long best = null;
        for (long due : dueTimes) {
            long candidate = Math.max(nextMorning, morning(due, 1));
            if (best == null || candidate < best) best = candidate;
        }
        return best;
    }

    static int overdueCount(List<Long> dueTimes, long now) {
        long start = dayStart(now);
        int count = 0;
        for (long due : dueTimes) {
            if (due < start) count++;
        }
        return count;
    }
}
