import Repos from '../../scenes/RedHatRepositories';
import Subscriptions from '../../scenes/Subscriptions';


// eslint-disable-next-line import/prefer-default-export
export const links = [
  {
    text: 'RH Repos',
    path: 'redhat_repositories',
    component: Repos,
  },
  {
    text: 'RH Subscriptions',
    path: 'xui/subscriptions',
    component: Subscriptions,
  },
];
