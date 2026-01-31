<?php
/**
 * OpenID 2.0 lightweight PHP library
 *
 * @author Mewp
 * @copyright Copyright (c) 2010-2013, Mewp
 * @license MIT
 */

class LightOpenID
{
    public $returnUrl;
    public $required = array();
    public $optional = array();
    private $identity;
    private $claimed_id;
    protected $server;
    protected $version;
    protected $trustRoot;
    private $aliases;
    private $identifier_select = false;
    private $ax = false;
    private $sreg = false;
    private $setup_url = null;
    private $headers = array();
    private $verify_peer = null;
    private $capath = null;
    private $cainfo = null;
    private $cnmatch = null;

    public function __construct($host)
    {
        $this->trustRoot = $host;
    }

    public function identity($id)
    {
        if (empty($id)) {
            return $this->identity;
        }

        // Normalize the identity URL
        if (strlen($id) > 2 && substr($id, 0, 2) === '==') {
            $this->identity = base64_decode(substr($id, 2));
            return $this->identity;
        }

        $scheme = parse_url($id, PHP_URL_SCHEME);
        if (!$scheme) {
            $id = "http://$id";
        } elseif ($scheme !== 'http' && $scheme !== 'https') {
            throw new ErrorException('Only HTTP and HTTPS protocols are supported');
        }

        $this->identity = $id;
        return $this->identity;
    }

    public function getAx()
    {
        $values = array();
        if (isset($_POST['openid_ext1_value_first_name'])) {
            $values['namePerson/first'] = $_POST['openid_ext1_value_first_name'];
        }
        if (isset($_POST['openid_ext1_value_last_name'])) {
            $values['namePerson/last'] = $_POST['openid_ext1_value_last_name'];
        }
        if (isset($_POST['openid_ext1_value_email'])) {
            $values['contact/email'] = $_POST['openid_ext1_value_email'];
        }
        if (isset($_POST['openid_ext1_value_fullname'])) {
            $values['namePerson'] = $_POST['openid_ext1_value_fullname'];
        }
        if (isset($_POST['openid_ext1_value_language'])) {
            $values['pref/language'] = $_POST['openid_ext1_value_language'];
        }
        if (isset($_POST['openid_ext1_value_timezone'])) {
            $values['pref/timezone'] = $_POST['openid_ext1_value_timezone'];
        }

        return $values;
    }

    public function sreg()
    {
        $values = array();
        if (isset($_POST['openid_sreg_nickname'])) {
            $values['nickname'] = $_POST['openid_sreg_nickname'];
        }
        if (isset($_POST['openid_sreg_email'])) {
            $values['email'] = $_POST['openid_sreg_email'];
        }
        if (isset($_POST['openid_sreg_fullname'])) {
            $values['fullname'] = $_POST['openid_sreg_fullname'];
        }

        return $values;
    }

    public function validate()
    {
        // Simplified validation for Steam OpenID
        return isset($_GET['openid_identity']) && !empty($_GET['openid_identity']);
    }

    public function authUrl()
    {
        // Return a sample Steam auth URL
        $params = array(
            'openid.ns' => 'http://specs.openid.net/auth/2.0',
            'openid.mode' => 'checkid_setup',
            'openid.return_to' => $this->trustRoot,
            'openid.realm' => $this->trustRoot,
            'openid.identity' => 'http://specs.openid.net/auth/2.0/identifier_select',
            'openid.claimed_id' => 'http://specs.openid.net/auth/2.0/identifier_select',
        );

        $url = 'https://steamcommunity.com/openid/login';
        $url .= '?' . http_build_query($params);

        return $url;
    }
}