from socorro.external.postgresql import job
import socorro.unittest.testlib.util as testutil

from unittestbase import PostgreSQLTestCase


#------------------------------------------------------------------------------
def setup_module():
    testutil.nosePrintModule(__file__)


#==============================================================================
class IntegrationTestJob(PostgreSQLTestCase):
    """Test socorro.external.postgresql.Job.Job class. """

    #--------------------------------------------------------------------------
    def setUp(self):
        """Set up this test class by populating the reports table with fake
        data. """
        super(IntegrationTestJob, self).setUp()

        cursor = self.connection.cursor()

        # Insert data
        cursor.execute("""
            INSERT INTO processors
            (id, name, startdatetime, lastseendatetime)
            VALUES
            (
                2, 'processor2', '2012-02-29T01:23:45.000000+00:00',
                '2012-02-29T01:23:45.000000+00:00'
            );
            INSERT INTO jobs VALUES
            (
                1, '', 'a1', 2, 0,
                '2012-02-29T01:23:45.000000+00:00',
                '2012-02-29T01:23:45.000000+00:00',
                '2012-02-29T01:23:45.000000+00:00',
                't', ''
            ),
            (
                2, '', 'a2', 2, 0,
                '2012-02-29T01:23:45.000000+00:00',
                '2012-02-29T01:23:45.000000+00:00',
                '2012-02-29T01:23:45.000000+00:00',
                't', ''
            )
        """)

        self.connection.commit()

    #--------------------------------------------------------------------------
    def tearDown(self):
        """Clean up the database, delete tables and functions. """
        cursor = self.connection.cursor()
        cursor.execute("""
            TRUNCATE jobs
            CASCADE
        """)
        self.connection.commit()
        super(IntegrationTestJob, self).tearDown()

    #--------------------------------------------------------------------------
    def test_get(self):
        jobs = job.Job(config=self.config)

        #......................................................................
        # Test 1: a valid job
        params = {
            "uuid": "a1"
        }
        res = jobs.get(**params)
        res_expected = {
            "hits": [
                {
                    "id": 1,
                    "pathname": "",
                    "uuid": "a1",
                    "owner": 2,
                    "priority": 0,
                    "queueddatetime": "2012-02-29T01:23:45.000000+00:00",
                    "starteddatetime": "2012-02-29T01:23:45.000000+00:00",
                    "completeddatetime": "2012-02-29T01:23:45.000000+00:00",
                    "success": True,
                    "message": ""
                }
            ],
            "total": 1
        }

        self.assertEqual(res, res_expected)

        #......................................................................
        # Test 2: an invalid job
        params = {
            "uuid": "b2"
        }
        res = jobs.get(**params)
        res_expected = {
            "hits": [],
            "total": 0
        }

        self.assertEqual(res, res_expected)

        #......................................................................
        # Test 3: missing argument
        params = {}
        self.assertRaises(job.MissingOrBadArgumentError,
                          jobs.get,
                          **params)
