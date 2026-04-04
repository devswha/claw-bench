import unittest

from palindrome import is_palindrome


class PalindromeTests(unittest.TestCase):
    def test_true_cases(self):
        self.assertTrue(is_palindrome(""))
        self.assertTrue(is_palindrome("racecar"))
        self.assertTrue(is_palindrome("abba"))

    def test_false_cases(self):
        self.assertFalse(is_palindrome("hello"))
        self.assertFalse(is_palindrome("python"))


if __name__ == "__main__":
    unittest.main()
