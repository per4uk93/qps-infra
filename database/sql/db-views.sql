set schema 'zafira';

--DELETE OR DETACH ALL TESTS WHERE CREATED_AT::date < '2016-01-01'

DROP MATERIALIZED VIEW IF EXISTS TOTAL_VIEW;
CREATE MATERIALIZED VIEW TOTAL_VIEW AS (
  SELECT row_number() OVER () AS ID,
         PROJECTS.NAME AS PROJECT,
         USERS.ID AS OWNER_ID,
         USERS.USERNAME AS OWNER,
         TEST_CONFIGS.ENV as ENV,
         sum( case when TESTS.STATUS = 'PASSED' then 1 else 0 end ) AS PASSED,
         sum( case when TESTS.STATUS = 'FAILED' AND TESTS.KNOWN_ISSUE=FALSE then 1 else 0 end ) AS FAILED,
         sum( case when TESTS.STATUS = 'FAILED' AND TESTS.KNOWN_ISSUE=TRUE then 1 else 0 end ) AS KNOWN_ISSUE,
         sum( case when TESTS.STATUS = 'SKIPPED' then 1 else 0 end ) AS SKIPPED,
         sum( case when TESTS.STATUS = 'ABORTED' then 1 else 0 end ) AS ABORTED,
         sum( case when TESTS.STATUS = 'IN_PROGRESS' then 1 else 0 end ) AS IN_PROGRESS,
         sum( case when TESTS.STATUS = 'QUEUED' then 1 else 0 end ) AS QUEUED,
         COUNT(*) AS TOTAL,
         date_trunc('month', TESTS.CREATED_AT) AS TESTED_AT,
         sum(EXTRACT(epoch FROM (TESTS.FINISH_TIME - TESTS.START_TIME))/60)::bigint as TOTAL_MINUTES,
         sum(EXTRACT(epoch FROM(TESTS.FINISH_TIME - TESTS.START_TIME))/3600)::bigint as TOTAL_HOURS,
         avg(TESTS.FINISH_TIME - TESTS.START_TIME) as AVG_TIME
  FROM TESTS INNER JOIN
    TEST_CASES ON TESTS.TEST_CASE_ID = TEST_CASES.ID INNER JOIN
    USERS ON TEST_CASES.PRIMARY_OWNER_ID = USERS.ID LEFT JOIN
    TEST_CONFIGS ON TESTS.TEST_CONFIG_ID = TEST_CONFIGS.ID LEFT JOIN
    PROJECTS ON TEST_CASES.PROJECT_ID = PROJECTS.ID
  WHERE TESTS.FINISH_TIME IS NOT NULL
        AND TESTS.START_TIME IS NOT NULL
        AND TESTS.START_TIME < date_trunc('month', current_date)
        AND TESTS.STATUS <> 'IN_PROGRESS'
        GROUP BY PROJECT, OWNER_ID, OWNER, ENV, TESTED_AT
  ORDER BY TESTED_AT
);

DROP INDEX IF EXISTS TOTAL_VIEW_INDEX;
CREATE UNIQUE INDEX TOTAL_VIEW_INDEX ON TOTAL_VIEW (ID);

DROP INDEX IF EXISTS TOTAL_VIEW_PROJECT_INDEX;
CREATE INDEX TOTAL_VIEW_PROJECT_INDEX ON TOTAL_VIEW (PROJECT);

DROP INDEX IF EXISTS TOTAL_VIEW_OWNER_ID_INDEX;
CREATE INDEX TOTAL_VIEW_OWNER_ID_INDEX ON TOTAL_VIEW (OWNER_ID);

DROP INDEX IF EXISTS TOTAL_VIEW_OWNER_INDEX;
CREATE INDEX TOTAL_VIEW_OWNER_INDEX ON TOTAL_VIEW (OWNER);

DROP INDEX IF EXISTS TOTAL_VIEW_ENV_INDEX;
CREATE INDEX TOTAL_VIEW_ENV_INDEX ON TOTAL_VIEW (ENV);

DROP INDEX IF EXISTS TOTAL_VIEW_TESTED_AT_INDEX;
CREATE INDEX TOTAL_VIEW_TESTED_AT_INDEX ON TOTAL_VIEW (TESTED_AT);

SELECT cron.schedule ('0 0 1 * *', $$REFRESH MATERIALIZED VIEW CONCURRENTLY ZAFIRA.TOTAL_VIEW$$);


--Tests for the period from the beginning of previous month till previous day incl.
DROP MATERIALIZED VIEW IF EXISTS BIMONTHLY_VIEW;
CREATE MATERIALIZED VIEW BIMONTHLY_VIEW AS (
  SELECT  row_number() OVER () AS ID,
          PROJECTS.NAME AS PROJECT,
          USERS.ID AS OWNER_ID,
          USERS.USERNAME AS OWNER,
          USERS.EMAIL AS EMAIL,
          TEST_RUNS.ENV as ENV,
          TEST_CONFIGS.PLATFORM as PLATFORM,
          TEST_CONFIGS.PLATFORM_VERSION as PLATFORM_VERSION,
          TEST_CONFIGS.BROWSER as BROWSER,
          TEST_CONFIGS.BROWSER_VERSION as BROWSER_VERSION,
          TEST_CONFIGS.APP_VERSION as BUILD,
          TEST_CONFIGS.DEVICE as DEVICE,
          TEST_CONFIGS.URL as URL,
          TEST_CONFIGS.LOCALE as LOCALE,
          TEST_CONFIGS.LANGUAGE as LANGUAGE,
          JOBS.JOB_URL AS JOB_URL,
          JOBS.NAME AS JOB_NAME,
          TEST_SUITES.NAME AS TEST_SUITE_NAME,
          TEST_SUITES.USER_ID AS JOB_OWNER_ID,
          TEST_RUNS.ID AS TEST_RUN_ID,
          TEST_RUNS.BUILD_NUMBER As JobBuild,
          '<a href="' || JOBS.JOB_URL  || '/' || CAST(TEST_RUNS.BUILD_NUMBER AS text) || '/eTAF_Report' || '" target="_blank">' || JOBS.NAME || '</a>' as eTAF_Report,
          '<a href="' || JOBS.JOB_URL  || '/' || CAST(TEST_RUNS.BUILD_NUMBER AS text) || '/rebuild/parameterized' || '" target="_blank">Rebuild</a>' as Rebuild,
          TEST_RUNS.ELAPSED AS Elapsed,
          TEST_RUNS.STARTED_AT AS Started,
          TEST_RUNS.CREATED_AT::date AS Updated,
          TEST_RUNS.UPSTREAM_JOB_ID AS UPSTREAM_JOB_ID,
          TEST_RUNS.UPSTREAM_JOB_BUILD_NUMBER AS UPSTREAM_JOB_BUILD_NUMBER,
          TEST_RUNS.SCM_URL AS SCM_URL,
          sum( case when TESTS.STATUS = 'PASSED' then 1 else 0 end ) AS PASSED,
          sum( case when TESTS.STATUS = 'FAILED' AND TESTS.KNOWN_ISSUE=FALSE then 1 else 0 end ) AS FAILED,
          sum( case when TESTS.STATUS = 'FAILED' AND TESTS.KNOWN_ISSUE=TRUE then 1 else 0 end ) AS KNOWN_ISSUE,
          sum( case when TESTS.STATUS = 'SKIPPED' then 1 else 0 end ) AS SKIPPED,
          sum( case when TESTS.STATUS = 'ABORTED' then 1 else 0 end ) AS ABORTED,
          sum( case when TESTS.STATUS = 'IN_PROGRESS' then 1 else 0 end ) AS IN_PROGRESS,
          sum( case when TESTS.STATUS = 'QUEUED' then 1 else 0 end ) AS QUEUED,
          count( TESTS.STATUS ) AS TOTAL,
          sum(EXTRACT(epoch FROM(TESTS.FINISH_TIME - TESTS.START_TIME))/3600)::bigint as TOTAL_HOURS,
	  sum(EXTRACT(epoch FROM (TESTS.FINISH_TIME - TESTS.START_TIME)))::bigint as TOTAL_SECONDS
  FROM TESTS INNER JOIN
    TEST_RUNS ON TEST_RUNS.ID=TESTS.TEST_RUN_ID INNER JOIN
    TEST_CASES ON TESTS.TEST_CASE_ID=TEST_CASES.ID LEFT JOIN
    TEST_CONFIGS ON TESTS.TEST_CONFIG_ID = TEST_CONFIGS.ID LEFT JOIN
    PROJECTS ON TEST_CASES.PROJECT_ID = PROJECTS.ID INNER JOIN
    JOBS ON TEST_RUNS.JOB_ID = JOBS.ID INNER JOIN
    USERS ON TEST_CASES.PRIMARY_OWNER_ID=USERS.ID INNER JOIN
    TEST_SUITES ON TEST_RUNS.TEST_SUITE_ID = TEST_SUITES.ID
  WHERE TESTS.CREATED_AT >= date_trunc('month', current_date - interval '1 month')
        AND TEST_RUNS.STARTED_AT >= date_trunc('month', current_date - interval '1 month')
        AND TEST_RUNS.STARTED_AT < current_date
        AND TESTS.STATUS <> 'IN_PROGRESS'
  GROUP BY PROJECT, TEST_RUNS.ID, USERS.ID, TEST_CONFIGS.PLATFORM, TEST_CONFIGS.PLATFORM_VERSION, TEST_CONFIGS.BROWSER, TEST_CONFIGS.BROWSER_VERSION,
    TEST_CONFIGS.DEVICE, TEST_CONFIGS.URL, TEST_CONFIGS.LOCALE, TEST_CONFIGS.LANGUAGE, TEST_CONFIGS.APP_VERSION, JOBS.JOB_URL, JOBS.NAME, TEST_SUITES.NAME, TEST_SUITES.USER_ID);

DROP INDEX IF EXISTS BIMONTHLY_VIEW_ID_INDEX;
CREATE UNIQUE INDEX BIMONTHLY_VIEW_ID_INDEX ON BIMONTHLY_VIEW (ID);

DROP INDEX IF EXISTS BIMONTHLY_VIEW_PROJECT_INDEX;
CREATE INDEX BIMONTHLY_VIEW_PROJECT_INDEX ON BIMONTHLY_VIEW (PROJECT);

DROP INDEX IF EXISTS BIMONTHLY_VIEW_OWNER_ID_INDEX;
CREATE INDEX BIMONTHLY_VIEW_OWNER_ID_INDEX ON BIMONTHLY_VIEW (OWNER_ID);

DROP INDEX IF EXISTS BIMONTHLY_VIEW_OWNER_INDEX;
CREATE INDEX BIMONTHLY_VIEW_OWNER_INDEX ON BIMONTHLY_VIEW (OWNER);

DROP INDEX IF EXISTS BIMONTHLY_VIEW_EMAIL_INDEX;
CREATE INDEX BIMONTHLY_VIEW_EMAIL_INDEX ON BIMONTHLY_VIEW (EMAIL);

DROP INDEX IF EXISTS BIMONTHLY_VIEW_ENV_INDEX;
CREATE INDEX BIMONTHLY_VIEW_ENV_INDEX ON BIMONTHLY_VIEW (ENV);

DROP INDEX IF EXISTS BIMONTHLY_VIEW_PLATFORM_INDEX;
CREATE INDEX BIMONTHLY_VIEW_PLATFORM_INDEX ON BIMONTHLY_VIEW (PLATFORM);

DROP INDEX IF EXISTS BIMONTHLY_VIEW_PLATFORM_VERSION_INDEX;
CREATE INDEX BIMONTHLY_VIEW_PLATFORM_VERSION_INDEX ON BIMONTHLY_VIEW (PLATFORM_VERSION);

DROP INDEX IF EXISTS BIMONTHLY_VIEW_BROWSER_INDEX;
CREATE INDEX BIMONTHLY_VIEW_BROWSER_INDEX ON BIMONTHLY_VIEW (BROWSER);

DROP INDEX IF EXISTS BIMONTHLY_VIEW_BROWSER_VERSION_INDEX;
CREATE INDEX BIMONTHLY_VIEW_BROWSER_VERSION_INDEX ON BIMONTHLY_VIEW (BROWSER_VERSION);

DROP INDEX IF EXISTS BIMONTHLY_VIEW_BROWSER_INDEX;
CREATE INDEX BIMONTHLY_VIEW_BROWSER_INDEX ON BIMONTHLY_VIEW (BUILD);

DROP INDEX IF EXISTS BIMONTHLY_VIEW_DEVICE_INDEX;
CREATE INDEX BIMONTHLY_VIEW_DEVICE_INDEX ON BIMONTHLY_VIEW (DEVICE);

DROP INDEX IF EXISTS BIMONTHLY_VIEW_URL_INDEX;
CREATE INDEX BIMONTHLY_VIEW_URL_INDEX ON BIMONTHLY_VIEW (URL);

DROP INDEX IF EXISTS BIMONTHLY_VIEW_LOCALE_INDEX;
CREATE INDEX BIMONTHLY_VIEW_LOCALE_INDEX ON BIMONTHLY_VIEW (LOCALE);

DROP INDEX IF EXISTS BIMONTHLY_VIEW_LANGUAGE_INDEX;
CREATE INDEX BIMONTHLY_VIEW_LANGUAGE_INDEX ON BIMONTHLY_VIEW (LANGUAGE);

DROP INDEX IF EXISTS BIMONTHLY_VIEW_JOB_INDEX;
CREATE INDEX BIMONTHLY_VIEW_JOB_INDEX ON BIMONTHLY_VIEW (JOB_URL);

DROP INDEX IF EXISTS BIMONTHLY_VIEW_TEST_SUITE_NAME_INDEX;
CREATE INDEX BIMONTHLY_VIEW_TEST_SUITE_NAME_INDEX ON BIMONTHLY_VIEW (TEST_SUITE_NAME);

DROP INDEX IF EXISTS BIMONTHLY_VIEW_JOB_OWNER_ID_INDEX;
CREATE INDEX BIMONTHLY_VIEW_JOB_OWNER_ID_INDEX ON BIMONTHLY_VIEW (JOB_OWNER_ID);

DROP INDEX IF EXISTS BIMONTHLY_VIEW_JOB_BUILD_INDEX;
CREATE INDEX BIMONTHLY_VIEW_JOB_BUILD_INDEX ON BIMONTHLY_VIEW (JobBuild);

DROP INDEX IF EXISTS BIMONTHLY_VIEW_ELAPSED_INDEX;
CREATE INDEX BIMONTHLY_VIEW_ELAPSED_INDEX ON BIMONTHLY_VIEW (Elapsed);

DROP INDEX IF EXISTS BIMONTHLY_VIEW_STARTED_INDEX;
CREATE INDEX BIMONTHLY_VIEW_STARTED_INDEX ON BIMONTHLY_VIEW (Started);

DROP INDEX IF EXISTS BIMONTHLY_VIEW_UPDATED_INDEX;
CREATE INDEX BIMONTHLY_VIEW_UPDATED_INDEX ON BIMONTHLY_VIEW (Updated);

DROP INDEX IF EXISTS BIMONTHLY_VIEW_ETAF_REPORT_INDEX;
CREATE INDEX BIMONTHLY_VIEW_ETAF_REPORT_INDEX ON BIMONTHLY_VIEW (eTAF_Report);

DROP INDEX IF EXISTS BIMONTHLY_VIEW_REBUILD_INDEX;
CREATE INDEX BIMONTHLY_VIEW_REBUILD_INDEX ON BIMONTHLY_VIEW (Rebuild);

DROP INDEX IF EXISTS BIMONTHLY_VIEW_UPSTREAM_JOB_ID_INDEX;
CREATE INDEX BIMONTHLY_VIEW_UPSTREAM_JOB_ID_INDEX ON BIMONTHLY_VIEW (UPSTREAM_JOB_ID);

DROP INDEX IF EXISTS BIMONTHLY_VIEW_UPSTREAM_JOB_BUILD_NUMBER_INDEX;
CREATE INDEX BIMONTHLY_VIEW_UPSTREAM_JOB_BUILD_NUMBER_INDEX ON BIMONTHLY_VIEW (UPSTREAM_JOB_BUILD_NUMBER);

SELECT cron.schedule ('0 7 * * *', $$REFRESH MATERIALIZED VIEW CONCURRENTLY ZAFIRA.BIMONTHLY_VIEW$$);


DROP VIEW IF EXISTS NIGHTLY_FAILURES_VIEW;
CREATE VIEW NIGHTLY_FAILURES_VIEW AS (
  SELECT
    row_number() OVER () AS ID,
    PROJECTS.NAME AS PROJECT,
    TESTS.ID AS TEST_ID,
    TESTS.NAME AS TEST_NAME,
    USERS.ID AS OWNER_ID,
    USERS.USERNAME AS OWNER,
    USERS.EMAIL AS EMAIL,
    TEST_RUNS.ENV AS ENV,
    TEST_CONFIGS.PLATFORM AS PLATFORM,
    TEST_CONFIGS.BROWSER AS BROWSER,
    JOBS.JOB_URL AS JOB_URL,
    JOBS.NAME AS JOB_NAME,
    TEST_SUITES.NAME AS TEST_SUITE_NAME,
    TEST_RUNS.BUILD_NUMBER AS JOBBUILD,
    '<a href="#!/tests/runs/' || TEST_RUNS.ID || '" target="_blank">' || JOBS.NAME || '</a>' AS REPORT,
    '<a href="' || JOBS.JOB_URL || '/' || TEST_RUNS.build_number || '/eTAF_Report' || '" target="_blank">' || JOBS.NAME || '</a>' AS ETAF_REPORT,
    '<a href="' || JOBS.JOB_URL || '/' || TEST_RUNS.build_number || '/rebuild/parameterized' || '" target="_blank">Rebuild</a>' AS REBUILD,
    TEST_RUNS.ID AS TEST_RUN_ID,
    TEST_RUNS.UPSTREAM_JOB_ID AS UPSTREAM_JOB_ID,
    TEST_RUNS.UPSTREAM_JOB_BUILD_NUMBER AS UPSTREAM_JOB_BUILD_NUMBER,
    TESTS.MESSAGE AS MESSAGE,
    TESTS.MESSAGE_HASH_CODE AS MESSAGE_HASHCODE,
    TESTS.BLOCKER AS TEST_BLOCKER,
    TESTS.KNOWN_ISSUE AS TEST_KNOWN_ISSUE
  FROM TESTS
    JOIN TEST_RUNS ON TEST_RUNS.ID = TESTS.TEST_RUN_ID
    JOIN TEST_CASES ON TESTS.TEST_CASE_ID = TEST_CASES.ID
    LEFT JOIN PROJECTS ON TEST_CASES.PROJECT_ID = PROJECTS.ID
    JOIN USERS ON TEST_CASES.PRIMARY_OWNER_ID = USERS.ID
    LEFT JOIN TEST_CONFIGS ON TESTS.TEST_CONFIG_ID = TEST_CONFIGS.ID
    JOIN JOBS ON TEST_RUNS.JOB_ID = JOBS.ID
    JOIN TEST_SUITES ON TEST_RUNS.TEST_SUITE_ID = TEST_SUITES.ID
  WHERE TESTS.CREATED_AT >= current_date AND
        TEST_RUNS.STARTED_AT >= current_date AND
        TESTS.STATUS = 'FAILED'
  GROUP BY PROJECTS.NAME, TESTS.ID, TEST_RUNS.ID, USERS.ID, TEST_RUNS.ENV, TEST_CONFIGS.PLATFORM, TEST_CONFIGS.BROWSER, TEST_RUNS.BUILD_NUMBER, TEST_CONFIGS.URL, TEST_SUITES.NAME, JOBS.NAME, JOBS.JOB_URL
);

DROP MATERIALIZED VIEW IF EXISTS TEST_CASE_HEALTH_VIEW;
CREATE MATERIALIZED VIEW TEST_CASE_HEALTH_VIEW AS (
  SELECT ROW_NUMBER() OVER () AS ID,
         PROJECTS.NAME AS PROJECT,
         TEST_CASES.ID AS TEST_CASE_ID,
         TEST_CASES.TEST_METHOD AS TEST_METHOD_NAME,
         SUM( CASE WHEN TESTS.STATUS = 'PASSED' THEN 1 ELSE 0 END ) AS PASSED,
         SUM( CASE WHEN TESTS.STATUS = 'FAILED' AND TESTS.KNOWN_ISSUE=FALSE THEN 1 ELSE 0 END ) AS FAILED,
         SUM( CASE WHEN TESTS.STATUS = 'FAILED' AND TESTS.KNOWN_ISSUE=TRUE THEN 1 ELSE 0 END ) AS KNOWN_ISSUE,
         SUM( CASE WHEN TESTS.STATUS = 'SKIPPED' THEN 1 ELSE 0 END ) AS SKIPPED,
         SUM( CASE WHEN TESTS.STATUS = 'ABORTED' THEN 1 ELSE 0 END ) AS ABORTED,
         SUM( CASE WHEN TESTS.STATUS = 'IN_PROGRESS' THEN 1 ELSE 0 END ) AS IN_PROGRESS,
         SUM( case when TESTS.STATUS = 'QUEUED' then 1 else 0 end ) AS QUEUED,
         COUNT(*) AS TOTAL,
         SUM(EXTRACT(EPOCH FROM (TESTS.FINISH_TIME - TESTS.START_TIME))/60)::BIGINT AS TOTAL_MINUTES,
         SUM(EXTRACT(EPOCH FROM(TESTS.FINISH_TIME - TESTS.START_TIME))/3600)::BIGINT AS TOTAL_HOURS,
         AVG(EXTRACT(EPOCH FROM(TESTS.FINISH_TIME - TESTS.START_TIME))) AS AVG_TIME,
         MIN(EXTRACT(EPOCH FROM(TESTS.FINISH_TIME - TESTS.START_TIME))) AS MIN_TIME,
         MAX(EXTRACT(EPOCH FROM(TESTS.FINISH_TIME - TESTS.START_TIME))) AS MAX_TIME,
         ROUND(SUM( CASE WHEN TESTS.STATUS = 'PASSED' THEN 1 ELSE 0 END )*100/COUNT(*)) AS STABILITY,
         ROUND(SUM( CASE WHEN TESTS.STATUS = 'FAILED' AND TESTS.KNOWN_ISSUE=FALSE THEN 1 ELSE 0 END )*100/COUNT(*)) AS FAILURE,
         ROUND(SUM( CASE WHEN TESTS.STATUS = 'FAILED' AND TESTS.KNOWN_ISSUE=TRUE THEN 1 ELSE 0 END )*100/COUNT(*)) AS KNOWN_FAILURE,
         ROUND(SUM( CASE WHEN TESTS.STATUS = 'SKIPPED' THEN 1 ELSE 0 END )*100/COUNT(*)) AS OMISSION,
         ROUND(SUM( CASE WHEN TESTS.STATUS = 'ABORTED' THEN 1 ELSE 0 END )*100/COUNT(*)) AS INTERRUPT,
         ROUND(SUM( CASE WHEN TESTS.STATUS = 'QUEUED' THEN 1 ELSE 0 END )*100/COUNT(*)) AS QUEUE,
         DATE_TRUNC('MONTH', TESTS.CREATED_AT) AS TESTED_AT
  FROM TESTS INNER JOIN
    TEST_CASES ON TESTS.TEST_CASE_ID = TEST_CASES.ID LEFT JOIN
    PROJECTS ON TEST_CASES.PROJECT_ID = PROJECTS.ID
  WHERE TESTS.FINISH_TIME IS NOT NULL
        AND TESTS.START_TIME IS NOT NULL
        AND TESTS.STATUS <> 'IN_PROGRESS'
  GROUP BY PROJECTS.ID, TEST_CASES.ID, TESTED_AT
  ORDER BY TESTED_AT
);

DROP INDEX IF EXISTS TEST_CASE_HEALTH_VIEW_INDEX;
CREATE UNIQUE INDEX TEST_CASE_HEALTH_VIEW_INDEX ON TEST_CASE_HEALTH_VIEW (ID);

DROP INDEX IF EXISTS TEST_CASE_HEALTH_VIEW_TEST_METHOD_NAME_INDEX;
CREATE INDEX TEST_CASE_HEALTH_VIEW_TEST_METHOD_NAME_INDEX ON TEST_CASE_HEALTH_VIEW (TEST_METHOD_NAME);

DROP INDEX IF EXISTS TEST_CASE_HEALTH_VIEW_STABILITY_INDEX;
CREATE INDEX TEST_CASE_HEALTH_VIEW_STABILITY_INDEX ON TEST_CASE_HEALTH_VIEW (STABILITY);

DROP INDEX IF EXISTS TEST_CASE_HEALTH_VIEW_TESTED_AT_INDEX;
CREATE INDEX TEST_CASE_HEALTH_VIEW_TESTED_AT_INDEX ON TEST_CASE_HEALTH_VIEW (TESTED_AT);

SELECT cron.schedule ('0 7 * * *', $$REFRESH MATERIALIZED VIEW CONCURRENTLY ZAFIRA.TEST_CASE_HEALTH_VIEW$$);

DROP VIEW IF EXISTS MONTHLY_VIEW;
CREATE VIEW MONTHLY_VIEW AS (
  SELECT  row_number() OVER () AS ID,
          PROJECTS.NAME AS PROJECT,
          USERS.ID AS OWNER_ID,
          USERS.USERNAME AS OWNER,
          USERS.EMAIL AS EMAIL,
          TEST_RUNS.ENV as ENV,
          TEST_CONFIGS.PLATFORM as PLATFORM,
          TEST_CONFIGS.PLATFORM_VERSION as PLATFORM_VERSION,
          TEST_CONFIGS.BROWSER as BROWSER,
          TEST_CONFIGS.BROWSER_VERSION as BROWSER_VERSION,
          TEST_CONFIGS.APP_VERSION as BUILD,
          TEST_CONFIGS.DEVICE as DEVICE,
          TEST_CONFIGS.URL as URL,
          TEST_CONFIGS.LOCALE as LOCALE,
          TEST_CONFIGS.LANGUAGE as LANGUAGE,
          JOBS.JOB_URL AS JOB_URL,
          JOBS.NAME AS JOB_NAME,
          TEST_SUITES.USER_ID AS JOB_OWNER_ID,
          TEST_SUITES.NAME AS TEST_SUITE_NAME,
          TEST_RUNS.ID AS TEST_RUN_ID,
          TEST_RUNS.BUILD_NUMBER As JobBuild,
          '<a href="' || JOBS.JOB_URL  || '/' || CAST(TEST_RUNS.BUILD_NUMBER AS text) || '/eTAF_Report' || '" target="_blank">' || JOBS.NAME || '</a>' as eTAF_Report,
          '<a href="' || JOBS.JOB_URL  || '/' || CAST(TEST_RUNS.BUILD_NUMBER AS text) || '/rebuild/parameterized' || '" target="_blank">Rebuild</a>' as Rebuild,
          TEST_RUNS.ELAPSED AS Elapsed,
          TEST_RUNS.STARTED_AT AS Started,
          TEST_RUNS.CREATED_AT::date AS Updated,
          TEST_RUNS.UPSTREAM_JOB_ID AS UPSTREAM_JOB_ID,
          TEST_RUNS.UPSTREAM_JOB_BUILD_NUMBER AS UPSTREAM_JOB_BUILD_NUMBER,
          TEST_RUNS.SCM_URL AS SCM_URL,
          sum( case when TESTS.STATUS = 'PASSED' then 1 else 0 end ) AS PASSED,
          sum( case when TESTS.STATUS = 'FAILED' AND TESTS.KNOWN_ISSUE=FALSE then 1 else 0 end ) AS FAILED,
          sum( case when TESTS.STATUS = 'FAILED' AND TESTS.KNOWN_ISSUE=TRUE then 1 else 0 end ) AS KNOWN_ISSUE,
          sum( case when TESTS.STATUS = 'SKIPPED' then 1 else 0 end ) AS SKIPPED,
          sum( case when TESTS.STATUS = 'ABORTED' then 1 else 0 end ) AS ABORTED,
          sum( case when TESTS.STATUS = 'IN_PROGRESS' then 1 else 0 end ) AS IN_PROGRESS,
          sum( case when TESTS.STATUS = 'QUEUED' then 1 else 0 end ) AS QUEUED,
          count( TESTS.STATUS ) AS TOTAL,
          sum(EXTRACT(epoch FROM(TESTS.FINISH_TIME - TESTS.START_TIME))/3600)::bigint as TOTAL_HOURS
  FROM TESTS INNER JOIN
    TEST_RUNS ON TEST_RUNS.ID=TESTS.TEST_RUN_ID INNER JOIN
    TEST_CASES ON TESTS.TEST_CASE_ID=TEST_CASES.ID LEFT JOIN
    TEST_CONFIGS ON TESTS.TEST_CONFIG_ID = TEST_CONFIGS.ID LEFT JOIN
    PROJECTS ON TEST_CASES.PROJECT_ID = PROJECTS.ID INNER JOIN
    JOBS ON TEST_RUNS.JOB_ID = JOBS.ID INNER JOIN
    USERS ON TEST_CASES.PRIMARY_OWNER_ID=USERS.ID INNER JOIN
    TEST_SUITES ON TEST_RUNS.TEST_SUITE_ID = TEST_SUITES.ID
  WHERE TESTS.CREATED_AT >= date_trunc('month', current_date)
        AND TEST_RUNS.STARTED_AT >= date_trunc('month', current_date)
        AND TESTS.STATUS <> 'IN_PROGRESS'
  GROUP BY PROJECT, TEST_RUNS.ID, USERS.ID, TEST_CONFIGS.PLATFORM, TEST_CONFIGS.PLATFORM_VERSION, TEST_CONFIGS.BROWSER, TEST_CONFIGS.BROWSER_VERSION,
    TEST_CONFIGS.DEVICE, TEST_CONFIGS.URL, TEST_CONFIGS.LOCALE, TEST_CONFIGS.LANGUAGE, TEST_CONFIGS.APP_VERSION, JOBS.JOB_URL, TEST_SUITES.NAME, JOBS.NAME, TEST_SUITES.USER_ID);

DROP VIEW IF EXISTS WEEKLY_VIEW;
CREATE VIEW WEEKLY_VIEW AS (
  SELECT  row_number() OVER () AS ID,
          PROJECTS.NAME AS PROJECT,
          USERS.ID AS OWNER_ID,
          USERS.USERNAME AS OWNER,
          USERS.EMAIL AS EMAIL,
          TEST_RUNS.ENV as ENV,
          TEST_CONFIGS.PLATFORM as PLATFORM,
          TEST_CONFIGS.PLATFORM_VERSION as PLATFORM_VERSION,
          TEST_CONFIGS.BROWSER as BROWSER,
          TEST_CONFIGS.BROWSER_VERSION as BROWSER_VERSION,
          TEST_CONFIGS.APP_VERSION as BUILD,
          TEST_CONFIGS.DEVICE as DEVICE,
          TEST_CONFIGS.URL as URL,
          TEST_CONFIGS.LOCALE as LOCALE,
          TEST_CONFIGS.LANGUAGE as LANGUAGE,
          JOBS.JOB_URL AS JOB_URL,
          JOBS.NAME AS JOB_NAME,
          TEST_SUITES.USER_ID AS JOB_OWNER_ID,
          TEST_SUITES.NAME AS TEST_SUITE_NAME,
          TEST_RUNS.ID AS TEST_RUN_ID,
          TEST_RUNS.BUILD_NUMBER As JobBuild,
          '<a href="' || JOBS.JOB_URL  || '/' || CAST(TEST_RUNS.BUILD_NUMBER AS text) || '/eTAF_Report' || '" target="_blank">' || JOBS.NAME || '</a>' as eTAF_Report,
          '<a href="' || JOBS.JOB_URL  || '/' || CAST(TEST_RUNS.BUILD_NUMBER AS text) || '/rebuild/parameterized' || '" target="_blank">Rebuild</a>' as Rebuild,
          TEST_RUNS.ELAPSED AS Elapsed,
          TEST_RUNS.STARTED_AT AS Started,
          TEST_RUNS.CREATED_AT::date AS Updated,
          TEST_RUNS.UPSTREAM_JOB_ID AS UPSTREAM_JOB_ID,
          TEST_RUNS.UPSTREAM_JOB_BUILD_NUMBER AS UPSTREAM_JOB_BUILD_NUMBER,
          TEST_RUNS.SCM_URL AS SCM_URL,
          sum( case when TESTS.STATUS = 'PASSED' then 1 else 0 end ) AS PASSED,
          sum( case when TESTS.STATUS = 'FAILED' AND TESTS.KNOWN_ISSUE=FALSE then 1 else 0 end ) AS FAILED,
          sum( case when TESTS.STATUS = 'FAILED' AND TESTS.KNOWN_ISSUE=TRUE then 1 else 0 end ) AS KNOWN_ISSUE,
          sum( case when TESTS.STATUS = 'SKIPPED' then 1 else 0 end ) AS SKIPPED,
          sum( case when TESTS.STATUS = 'ABORTED' then 1 else 0 end ) AS ABORTED,
          sum( case when TESTS.STATUS = 'IN_PROGRESS' then 1 else 0 end ) AS IN_PROGRESS,
          sum( case when TESTS.STATUS = 'QUEUED' then 1 else 0 end ) AS QUEUED,
          count( TESTS.STATUS ) AS TOTAL
  FROM TESTS INNER JOIN
    TEST_RUNS ON TEST_RUNS.ID=TESTS.TEST_RUN_ID INNER JOIN
    TEST_CASES ON TESTS.TEST_CASE_ID=TEST_CASES.ID LEFT JOIN
    TEST_CONFIGS ON TESTS.TEST_CONFIG_ID = TEST_CONFIGS.ID LEFT JOIN
    PROJECTS ON TEST_CASES.PROJECT_ID = PROJECTS.ID INNER JOIN
    JOBS ON TEST_RUNS.JOB_ID = JOBS.ID INNER JOIN
    USERS ON TEST_CASES.PRIMARY_OWNER_ID=USERS.ID INNER JOIN
    TEST_SUITES ON TEST_RUNS.TEST_SUITE_ID = TEST_SUITES.ID
  WHERE TESTS.CREATED_AT >= date_trunc('week', current_date)  - interval '2 day'
        AND TEST_RUNS.STARTED_AT >= date_trunc('week', current_date)  - interval '2 day'
  GROUP BY PROJECTS.NAME, TEST_RUNS.ID, USERS.ID, TEST_CONFIGS.PLATFORM, TEST_CONFIGS.PLATFORM_VERSION, TEST_CONFIGS.BROWSER, TEST_CONFIGS.BROWSER_VERSION,
    TEST_CONFIGS.DEVICE, TEST_CONFIGS.URL, TEST_CONFIGS.LOCALE, TEST_CONFIGS.LANGUAGE, TEST_CONFIGS.APP_VERSION, TEST_SUITES.NAME, JOBS.JOB_URL, JOBS.NAME, TEST_SUITES.USER_ID
);

DROP VIEW IF EXISTS NIGHTLY_VIEW;
CREATE VIEW NIGHTLY_VIEW AS (
  SELECT  row_number() OVER () AS ID,
          PROJECTS.NAME AS PROJECT,
          USERS.ID AS OWNER_ID,
          USERS.USERNAME AS OWNER,
          USERS.EMAIL AS EMAIL,
          TEST_RUNS.ENV as ENV,
          TEST_CONFIGS.PLATFORM as PLATFORM,
          TEST_CONFIGS.PLATFORM_VERSION as PLATFORM_VERSION,
          TEST_CONFIGS.BROWSER as BROWSER,
          TEST_CONFIGS.BROWSER_VERSION as BROWSER_VERSION,
          TEST_CONFIGS.APP_VERSION as BUILD,
          TEST_CONFIGS.DEVICE as DEVICE,
          TEST_CONFIGS.URL as URL,
          TEST_CONFIGS.LOCALE as LOCALE,
          TEST_CONFIGS.LANGUAGE as LANGUAGE,
          JOBS.JOB_URL AS JOB_URL,
          JOBS.NAME AS JOB_NAME,
          TEST_SUITES.USER_ID AS JOB_OWNER_ID,
          TEST_SUITES.NAME AS TEST_SUITE_NAME,
          TEST_RUNS.ID AS TEST_RUN_ID,
          TEST_RUNS.BUILD_NUMBER As JobBuild,
          '<a href="' || JOBS.JOB_URL  || '/' || CAST(TEST_RUNS.BUILD_NUMBER AS text) || '/eTAF_Report' || '" target="_blank">' || JOBS.NAME || '</a>' as eTAF_Report,
          '<a href="' || JOBS.JOB_URL  || '/' || CAST(TEST_RUNS.BUILD_NUMBER AS text) || '/rebuild/parameterized' || '" target="_blank">Rebuild</a>' as Rebuild,
          TEST_RUNS.ELAPSED AS Elapsed,
          TEST_RUNS.STARTED_AT AS Started,
          TEST_RUNS.CREATED_AT::date AS Updated,
          TEST_RUNS.UPSTREAM_JOB_ID AS UPSTREAM_JOB_ID,
          TEST_RUNS.UPSTREAM_JOB_BUILD_NUMBER AS UPSTREAM_JOB_BUILD_NUMBER,
          UPSTREAM_JOBS.NAME AS UPSTREAM_JOB_NAME,
          UPSTREAM_JOBS.JOB_URL AS UPSTREAM_JOB_URL,
          TEST_RUNS.SCM_URL AS SCM_URL,
          sum( case when TESTS.STATUS = 'PASSED' then 1 else 0 end ) AS PASSED,
          sum( case when TESTS.STATUS = 'FAILED' AND TESTS.KNOWN_ISSUE=FALSE then 1 else 0 end ) AS FAILED,
          sum( case when TESTS.STATUS = 'FAILED' AND TESTS.KNOWN_ISSUE=TRUE then 1 else 0 end ) AS KNOWN_ISSUE,
          sum( case when TESTS.STATUS = 'SKIPPED' then 1 else 0 end ) AS SKIPPED,
          sum( case when TESTS.STATUS = 'ABORTED' then 1 else 0 end ) AS ABORTED,
          sum( case when TESTS.STATUS = 'IN_PROGRESS' then 1 else 0 end ) AS IN_PROGRESS,
          sum( case when TESTS.STATUS = 'QUEUED' then 1 else 0 end ) AS QUEUED,
          count( TESTS.STATUS ) AS TOTAL
  FROM TESTS INNER JOIN
    TEST_RUNS ON TEST_RUNS.ID=TESTS.TEST_RUN_ID INNER JOIN
    TEST_CASES ON TESTS.TEST_CASE_ID=TEST_CASES.ID LEFT JOIN
    TEST_CONFIGS ON TESTS.TEST_CONFIG_ID = TEST_CONFIGS.ID LEFT JOIN
    PROJECTS ON TEST_CASES.PROJECT_ID = PROJECTS.ID INNER JOIN
    JOBS JOBS ON TEST_RUNS.JOB_ID = JOBS.ID LEFT JOIN
    JOBS UPSTREAM_JOBS ON TEST_RUNS.UPSTREAM_JOB_ID = UPSTREAM_JOBS.ID INNER JOIN
    USERS ON TEST_CASES.PRIMARY_OWNER_ID=USERS.ID INNER JOIN
    TEST_SUITES ON TEST_RUNS.TEST_SUITE_ID = TEST_SUITES.ID
  WHERE TESTS.CREATED_AT >= current_date
        AND TEST_RUNS.STARTED_AT >= current_date
  GROUP BY PROJECTS.NAME, TEST_RUNS.ID, USERS.ID, TEST_CONFIGS.PLATFORM, TEST_CONFIGS.PLATFORM_VERSION, TEST_CONFIGS.BROWSER, TEST_CONFIGS.BROWSER_VERSION,
    TEST_CONFIGS.DEVICE, TEST_CONFIGS.URL, TEST_CONFIGS.LOCALE, TEST_CONFIGS.LANGUAGE, TEST_CONFIGS.APP_VERSION, JOBS.ID, JOBS.JOB_URL, JOBS.NAME,
    UPSTREAM_JOBS.NAME, UPSTREAM_JOBS.JOB_URL, TEST_SUITES.NAME, TEST_SUITES.USER_ID
);