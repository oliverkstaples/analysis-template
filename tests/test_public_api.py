# Note that AI tools were used to generate tests
import analysis_template


def test_public_api():
    assert set(analysis_template.__all__) == set()
