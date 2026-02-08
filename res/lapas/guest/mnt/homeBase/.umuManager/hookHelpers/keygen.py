import secrets

def generate(alphabet, length):
    """
    Generate a cryptographically secure random string.

    Parameters
    ----------
    alphabet : str
        A string containing all characters that may be used in the generated key.
        For example: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".
    length : int
        The number of characters to generate.

    Returns
    -------
    str
        A randomly generated string of the specified length, composed of characters
        drawn from the provided alphabet.
    """
    return ''.join(secrets.choice(alphabet) for _ in range(length))
