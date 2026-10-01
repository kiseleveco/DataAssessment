SELECT day_diff, COUNT(*) AS n_persons
FROM #pair
GROUP BY day_diff
ORDER BY day_diff;
